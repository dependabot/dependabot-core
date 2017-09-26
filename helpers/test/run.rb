# frozen_string_literal: true

require "json"

request = JSON.parse($stdin.read)
case request["function"]
when "error"
  $stdout.write(JSON.dump(error: "Something went wrong"))
  exit 1
when "hard_error"
  puts "Oh no!"
  exit 0
else
  $stdout.write(JSON.dump(result: request))
end
