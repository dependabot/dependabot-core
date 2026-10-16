# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/update_checker/conflicting_dependency_resolver"

RSpec.describe Dependabot::Bun::UpdateChecker::ConflictingDependencyResolver do
  it "passes the installed version to the conflict helper" do
    dependency = Dependabot::Dependency.new(
      name: "brace-expansion",
      version: "2.1.2",
      requirements: [],
      package_manager: "bun"
    )
    resolver = described_class.new(
      dependency_files: project_dependency_files("javascript/no_lockfile"),
      credentials: []
    )
    allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_return([])

    expect(resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")).to be_empty
    expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess)
      .with(
        command: Dependabot::Bun::NativeHelpers.helper_path,
        function: "yarn:findConflictingDependencies",
        args: [a_kind_of(String), "brace-expansion", "2.1.4", "2.1.2"]
      )
  end
end
