# typed: true
# frozen_string_literal: true

require_relative "lib/bundler_version_constraint"

# Activate Bundler 4 by default with an upper bound to prevent unintended
# future major versions. Honor DEPENDABOT_BUNDLER_VERSION_CONSTRAINT (or its
# BUNDLER_VERSION_CONSTRAINT fallback) so staged rollouts and emergency
# rollbacks performed by the build script are respected at activation time.
bundler_constraint = BundlerVersionConstraint.resolve
gem "bundler", *BundlerVersionConstraint.activation_clauses(bundler_constraint)
require "bundler"
require "json"

$LOAD_PATH.unshift(File.expand_path("./lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("./monkey_patches", __dir__))

trap "HUP" do
  puts JSON.generate(error: "timeout", error_class: "Timeout::Error", trace: [])
  exit 2
end

# Bundler monkey patches
require "definition_ruby_version_patch"
require "definition_bundler_version_patch"
require "git_source_patch"

require "functions"

def output(obj)
  print JSON.dump(obj)
end

begin
  request = JSON.parse($stdin.read)

  function = request["function"]
  args = request["args"].transform_keys(&:to_sym)

  output({ result: Functions.send(function, **args) })
rescue StandardError => e
  output(
    { error: e.message, error_class: e.class, trace: e.backtrace }
  )
  exit(1)
end
