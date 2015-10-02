require "rspec/its"
require "webmock/rspec"

def fixture(name)
  File.read(File.join('spec', 'fixtures', name))
end
