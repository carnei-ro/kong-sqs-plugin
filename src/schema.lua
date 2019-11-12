local typedefs = require "kong.db.schema.typedefs"
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local REGIONS = {
  "ap-northeast-1", "ap-northeast-2",
  "ap-south-1",
  "ap-southeast-1", "ap-southeast-2",
  "ca-central-1",
  "eu-central-1",
  "eu-west-1", "eu-west-2",
  "sa-east-1",
  "us-east-1", "us-east-2",
  "us-gov-west-1",
  "us-west-1", "us-west-2",
}


return {
  name = plugin_name,
  fields = {
    { run_on = typedefs.run_on_first },
    { config = {
        type = "record",
        fields = {
          { timeout = {
              type = "number",
              required = true,
              default = 60000
          } },
          { aws_key = {
              type = "string",
              required = false
          } },
          { aws_secret = {
              type = "string",
              required = false
          } },
          { aws_iam_role = {
              type = "string",
              required = false
          } },
          { aws_metadata_url = {
              type = "string",
              default = "http://169.254.169.254/latest/meta-data/iam/security-credentials/",
              required = true
          } },
          { aws_region = {
              type = "string",
              required = true,
              one_of = REGIONS
          } },
          { queue_name = {
              type = "string",
              required = true
          } },
          { aws_account_id = {
              type = "string",
              required = true
          } },
          { port = typedefs.port { default = 443 }, },
          { store_creds_in_cache = {
              type = "boolean",
              default = false
          } },
          { cache_creds_ttl = {
              type = "number",
              default = 60
          } },
          { override_cache_creds_ttl = {
              type = "boolean",
              default = false
          } },
          { scan_options_attributes = {
              type = "boolean",
              default = false
          } },
        }
    } },
  },
}
