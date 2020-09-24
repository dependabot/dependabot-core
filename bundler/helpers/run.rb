require "bundler"
require "json"

require_relative "lib/functions"

def output(obj)
  print JSON.dump(obj)
end

begin
  request = JSON.parse(ARGV.join(""))

  function = request["function"]
  args = request["args"].transform_keys(&:to_sym)

  output Functions.send(function, **args)
rescue => error
  output({ error: error.message })
  exit(1)
end
