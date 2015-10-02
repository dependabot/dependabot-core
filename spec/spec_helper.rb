require "rspec/its"
require "webmock/rspec"
require "json"

def fixture(name)
  File.read(File.join('spec', 'fixtures', name))
end

def json_fixture(name)
  JSON.parse(fixture(name))
end
