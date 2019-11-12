--[[xml='<?xml version="1.0"?><SendMessageResponse xmlns="http://queue.amazonaws.com/doc/2012-11-05/"><SendMessageResult><MessageId>11f27472-3033-4b34-b204-d7be806689e4</MessageId><MD5OfMessageBody>03eda425a3227865e43fd2b67e46147c</MD5OfMessageBody></SendMessageResult><ResponseMetadata><RequestId>5f6d858b-9fb1-5034-978c-d0baeb5e6c32</RequestId></ResponseMetadata></SendMessageResponse>'

local MessageId, MD5OfMessageBody
string.gsub(xml,"MessageId>(.*)</MessageId", function(a) MessageId=a end)
string.gsub(xml,"MD5OfMessageBody>(.*)</MD5OfMessageBody", function(a) MD5OfMessageBody=a end)
print(MessageId)


m=string.gsub(xml,"MessageId>(.*)</MessageId", print)]]--

local h=kong.request.get_header('DelaySeconds')
local b = h and "string: " .. h or "string: "
ngx.say(b)

ngx.exit(200)
