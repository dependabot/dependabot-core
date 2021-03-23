require "bundler"
require "json"

$LOAD_PATH.unshift(File.expand_path("./lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("./monkey_patches", __dir__))

# Bundler monkey patches
require "definition_ruby_version_patch"
require "definition_bundler_version_patch"
require "git_source_patch"

require "functions"

MAX_BUNDLER_VERSION="2.0.0"

def validate_bundler_version!
  return true if correct_bundler_version?

  raise StandardError, "Called with Bundler '#{Bundler::VERSION}', expected < '#{MAX_BUNDLER_VERSION}'"
end

def correct_bundler_version?
  Gem::Version.new(Bundler::VERSION) < Gem::Version.new(MAX_BUNDLER_VERSION)
end

def output(obj)
  print JSON.dump(obj)
end

begin
  validate_bundler_version!

  request = JSON.parse($stdin.read)

  function = request["function"]
  args = request["args"].transform_keys(&:to_sym)

  output({ result: Functions.send(function, **args) })
rescue => error
  output(
    { error: error.message, error_class: error.class, trace: error.backtrace }
  )
  exit(1)
end
