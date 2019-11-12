package = "kong-sqs-plugin"
version = "1.0.0-0"

source = {
 url    = "git@github.com:carnei-ro/kong-sqs-plugin.git",
 branch = "master"
}

description = {
  summary = "a kong plugin to post messages on a SQS Queue",
}

dependencies = {
  "lua ~> 5.1"
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.kong-sqs-plugin.schema"] = "src/schema.lua",
    ["kong.plugins.kong-sqs-plugin.v4"] = "src/v4.lua",
    ["kong.plugins.kong-sqs-plugin.handler"] = "src/handler.lua",
  }
}