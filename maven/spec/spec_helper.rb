# typed: strict
# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

require "dependabot/experiments"
require "dependabot/maven/native_helpers"

RSpec.configure do |config|
  # Specs run with the dependency tree scan on, as it will be in production. Specs that
  # check the flag-off path turn it off themselves.
  #
  # The scan itself is faked by default so specs never run Maven or reach the network:
  # it writes no tree, so a parse returns only the declared dependencies. Specs that
  # need a tree stub `run_mvn_dependency_tree_plugin` with canned JSON output.
  config.before do
    Dependabot::Experiments.register(:maven_transitive_dependencies, true)
    allow(Dependabot::Maven::NativeHelpers).to receive(:run_mvn_dependency_tree_plugin)
  end
end
