require "bundler"
require "json"

require_relative "lib/functions"

def output(obj)
  print JSON.dump(obj)
end

begin
  request = JSON.parse($stdin.read)

  function = request["function"]
  args = request["args"].transform_keys(&:to_sym)

  output({ result: Functions.send(function, **args) })
rescue => error
  output({ error: error.message })
  exit(1)
end
