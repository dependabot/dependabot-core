# frozen_string_literal: true

require "logger"
require "bundler"
require "json"
require "logger"

$logger = Logger.new($stderr, formatter: proc { |severity, datetime, progname, msg|
  JSON.generate(msg.is_a?(Hash) ? msg : { msg: msg }) + "\n"
})
$LOAD_PATH.unshift(File.expand_path("./lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("./monkey_patches", __dir__))

trap "HUP" do
  With.tracer.disable
  puts JSON.generate(error: "timeout", error_class: "Timeout::Error", trace: With.stacktrace)
  exit 2
end

class With
  def self.stacktrace
    @stacktrace ||= []
  end

  def self.tracer
    @tracer ||= TracePoint.new(:call) do |x|
      stacktrace << { path: x.path, lineno: x.lineno, clazz: x.defined_class, method: x.method_id, args: args_from(x) }
    rescue => error
      $logger.error({ msg: error, stacktrace: error.backtrace })
    end
  end

  def self.args_from(trace)
    trace.parameters.map(&:last).map { |x| [x, trace.binding.eval(x.to_s)] }.to_h
  end

  def self.locals_from(trace)
    trace.binding.local_variables.map { |x| [x, trace.binding.local_variable_get(x)] }.to_h
  end

  def self.trace
    tracer.enable
    yield
  ensure
    tracer.disable
  end
end

# Bundler monkey patches
require "definition_ruby_version_patch"
require "definition_bundler_version_patch"
require "git_source_patch"

require "functions"

MAX_BUNDLER_VERSION = "2.0.0"

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

  With.trace do
    output({ result: Functions.send(function, **args) })
  end
rescue StandardError => e
  output(
    { error: e.message, error_class: e.class, trace: e.backtrace }
  )
  exit(1)
end
