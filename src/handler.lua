local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local aws_v4            = require ("kong.plugins." .. plugin_name .. ".v4")

local plugin            = require("kong.plugins.base_plugin"):extend()

local http              = require "resty.http"
local cjson             = require "cjson.safe"
local meta              = require "kong.meta"
local constants         = require "kong.constants"
local resty_http        = require 'resty.http'

local tostring          = tostring
local tonumber          = tonumber
local type              = type
local fmt               = string.format
local ngx_encode_base64 = ngx.encode_base64
local ngx_time          = ngx.time
local string_match      = string.match
local os_time           = os.time
local concat            = table.concat
local escape            = ngx.escape_uri
local ipairs            = ipairs

local AWS_PORT = 443

local function iso8601_to_epoch(date_iso8601)
  local inYear, inMonth, inDay, inHour, inMinute, inSecond, inZone = string_match(date_iso8601, '^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)(.-)$')
  local zHours, zMinutes = string_match(inZone, '^(.-):(%d%d)$')
  local returnTime = os_time({year=inYear, month=inMonth, day=inDay, hour=inHour, min=inMinute, sec=inSecond, isdst=false})
  if zHours then
    returnTime = returnTime - ((tonumber(zHours)*3600) + (tonumber(zMinutes)*60))
  end
  return returnTime
end

local function get_keys_from_metadata(iam_role,metadata_url)
  local httpc = resty_http:new()
  httpc:set_timeout(300) -- set timeout to 300ms

  local res, err = httpc:request_uri(metadata_url .. iam_role, {
        ssl_verify = false,
        keepalive  = false
  })

  if err then
    kong.response.exit(500, { message = "Could not get keys from meta-data endpoint", error = "function response: " .. err })
  end

  if not res then
    kong.response.exit(500, { message = "Empty response from meta-data endpoint", error = "function response: " .. tostring(err) })
  end

  if res.status ~= 200 then
    kong.response.exit(500, { message = "Not OK (HTTP 200) response from meta-data endpoint", error = "Not OK (HTTP 200) response from meta-data endpoint" })
  end

  local body = cjson.decode(res.body)
  local expiration = iso8601_to_epoch(body.Expiration) - ngx_time() -- aws keys auto regenerates 5 min before expiration. Maybe have to change this.
  return { ["AccessKeyId"] = body.AccessKeyId, ["SecretAccessKey"] = body.SecretAccessKey, ["Token"] = body.Token }, nil, expiration
end


local function get_keys_from_cache(iam_role,metadata_url,override_ttl,ttl)
    if override_ttl then
      local cred, err = kong.cache:get(iam_role .. "_cred", {ttl=ttl} , get_keys_from_metadata, iam_role, metadata_url)
    else
      local cred, err = kong.cache:get(iam_role .. "_cred", nil , get_keys_from_metadata, iam_role, metadata_url)
    end
    if err then
      kong.response.exit(500, { message = "Could not get/put " .. iam_role .. " credentials from/into cache", error = "Could not get/put " .. iam_role .. " credentials from/into cache" })
    end
    if cred then
      return cred.AccessKeyId, cred.SecretAccessKey, cred.Token
    end
    return nil
end


function plugin:new()
  plugin.super.new(self, plugin_name)
end


function plugin:access(conf)
  plugin.super.access(self)
  local var=ngx.var

  local body, err, mimetype = kong.request.get_body()
  if err then
    kong.response.exit(400, { message = "Payload required. Content-Type: 'application/json' or 'application/x-www-form-urlencoded'" })
  end

  local message_body = escape(cjson.encode(body))

  local query = concat({'Action=SendMessage&MessageBody=' , message_body})

  if conf.scan_options_attributes then
    for _,header in ipairs ({'DelaySeconds', 'Expires', 'MessageDeduplicationId', 'MessageGroupId'}) do
      local opt = kong.request.get_header(header)
      query = opt and concat({query , '&', header, '=', escape(opt)}) or query
    end
  end

  local host = fmt("sqs.%s.amazonaws.com", conf.aws_region)
  local path = fmt("/%s/%s", conf.aws_account_id, conf.queue_name)

  local port = conf.port or AWS_PORT

  local aws_key, aws_secret, aws_token
  if conf.aws_key == nil and conf.aws_secret == nil and conf.aws_iam_role ~= nil then
    if conf.store_creds_in_cache then
      aws_key, aws_secret, aws_token = get_keys_from_cache(conf.aws_iam_role, conf.aws_metadata_url, conf.override_cache_creds_ttl, conf.cache_creds_ttl)
    else
      local cred, e, ttl = get_keys_from_metadata(conf.aws_iam_role, conf.aws_metadata_url)
      if cred and e == nil then
        aws_key, aws_secret, aws_token = cred.AccessKeyId, cred.SecretAccessKey, cred.Token
      end
    end
  else
    aws_key = conf.aws_key
    aws_secret = conf.aws_secret
  end

  local opts = {
    region = conf.aws_region,
    service = "sqs",
    method = "GET",
    headers = {
      ["Content-Type"] = "application/x-amz-json-1.1",
    },
    path = path,
    host = host,
    port = port,
    access_key = aws_key,
    secret_key = aws_secret,
    query = query
  }

  if aws_token then
    opts["headers"]['X-Amz-Security-Token'] = aws_token
  end

  local request, err = aws_v4(opts)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  -- Trigger request
  local client = http.new()
  client:set_timeout(conf.timeout)
  client:connect(host, port)
  local ok, err = client:ssl_handshake()
  if not ok then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local res, err = client:request {
    method = "GET",
    path = request.url,
    body = request.body,
    headers = request.headers
  }
  if not res then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local content = res:read_body()
  local headers = res.headers

  if var.http2 then
    headers["Connection"] = nil
    headers["Keep-Alive"] = nil
    headers["Proxy-Connection"] = nil
    headers["Upgrade"] = nil
    headers["Transfer-Encoding"] = nil
  end

  local ok, err = client:close()
  if not ok then
    kong.log.err(err)
    return kong.response.exit(500, { message = "Could not close" })
  end

  if res.status == 200 then
    local MD5OfMessageBody=content:match("MD5OfMessageBody>(.*)</MD5OfMessageBody")
    local MessageId=content:match("MessageId>(.*)</MessageId")
    content=cjson.encode({
      MessageId=MessageId,
      MD5OfMessageBody=MD5OfMessageBody,
    })
    headers['Content-Type']='application/json'
  end

  return kong.response.exit(res.status, content, headers)
end


plugin.PRIORITY = 750
plugin.VERSION = "1.0.0-0"


return plugin
