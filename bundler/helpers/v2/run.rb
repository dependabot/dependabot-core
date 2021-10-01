# frozen_string_literal: true

require "bundler"
require "json"
require "timeout"

$LOAD_PATH.unshift(File.expand_path("./lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("./monkey_patches", __dir__))

# Bundler monkey patches
require "definition_ruby_version_patch"
require "definition_bundler_version_patch"
require "git_source_patch"

require "functions"

MIN_BUNDLER_VERSION = "2.1.0"

def validate_bundler_version!
  return true if correct_bundler_version?

  raise StandardError, "Called with Bundler '#{Bundler::VERSION}', expected >= '#{MIN_BUNDLER_VERSION}'"
end

def correct_bundler_version?
  Gem::Version.new(Bundler::VERSION) >= Gem::Version.new(MIN_BUNDLER_VERSION)
end

def output(obj)
  print JSON.dump(obj)
end

begin
  validate_bundler_version!

  request = JSON.parse($stdin.read)

  function = request["function"]
  args = request["args"].transform_keys(&:to_sym)

  Timeout.timeout(120) do
    output({ result: Functions.send(function, **args) })
  end
rescue StandardError => e
  output({ error: e.message, error_class: e.class, trace: e.backtrace })
  exit(1)
end
