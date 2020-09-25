require "bundler"
require "json"

require_relative "monkey_patches/bundler/definition_ruby_version_patch"
require_relative "monkey_patches/bundler/definition_bundler_version_patch"
require_relative "monkey_patches/bundler/git_source_patch"
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
