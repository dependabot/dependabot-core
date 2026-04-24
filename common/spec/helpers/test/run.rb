# typed: false
# frozen_string_literal: true

# rubocop:disable RSpec/Output -- This is a subprocess helper, not a spec. It must write to stdout/stderr.

require "json"

request = JSON.parse($stdin.read)
case request["function"]
when "error"
  $stdout.write(JSON.dump(error: "Something went wrong"))
  exit 1
when "sensitive_error"
  $stdout.write(JSON.dump(error: "Something went wrong: https://username:secret@www.example.com"))
  exit 1
when "useful_error"
  $stderr.write("Some useful error")
  exit 1
when "hard_error"
  puts "Oh no!"
  exit 0
when "killed"
  # SIGKILL the helper, which is what the kernel OOMKiller might do.
  Process.kill("KILL", Process.pid)
else
  $stdout.write(JSON.dump(result: request))
end
# rubocop:enable RSpec/Output
