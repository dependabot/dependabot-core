# frozen_string_literal: true
require "json"

request = JSON.parse($stdin.read)
if request["method"] == "error"
  puts "An error occurred"
else
  $stdout.write(JSON.dump(result: request))
end
