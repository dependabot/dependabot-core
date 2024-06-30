# typed: strict
# frozen_string_literal: true

gem "bundler", "~> 1.17"
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
require "fileutils_keyword_splat_patch"
require "git_source_patch"
require "resolver_spec_group_sane_eql"
require "object_untaint_patch"

require "functions"

begin
  request = JSON.parse($stdin.read)

  function = request["function"]
  args = request["args"].transform_keys(&:to_sym)

  print JSON.dump({ result: Functions.send(function, **args) })
rescue StandardError => e
  print JSON.dump(
    { error: e.message, error_class: e.class, trace: e.backtrace }
  )
  exit(1)
end
