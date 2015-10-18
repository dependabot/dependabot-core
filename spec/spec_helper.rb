require "rspec/its"
require "webmock/rspec"
require "dotenv"

Dotenv.load("dummy-env")

require "./app/boot"

def fixture(*name)
  File.read(File.join("spec", "fixtures", File.join(*name)))
end
