require "rspec/its"
require "webmock/rspec"
require "dotenv"

Dotenv.load(File.expand_path("../../config/dummy-env", __FILE__))

require "./app/boot"

RSpec.configure do |config|
  config.color = true
  config.order = :rand
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.raise_errors_for_deprecations!
end

def fixture(*name)
  File.read(File.join("spec", "fixtures", File.join(*name)))
end
