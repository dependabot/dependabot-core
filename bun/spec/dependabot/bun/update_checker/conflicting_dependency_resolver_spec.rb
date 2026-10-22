# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/update_checker/conflicting_dependency_resolver"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe Dependabot::Bun::UpdateChecker::ConflictingDependencyResolver do
  extend T::Sig

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "brace-expansion", version: "2.1.2", requirements: [], package_manager: "bun"
    )
  end

  sig { returns(Dependabot::Bun::UpdateChecker::ConflictingDependencyResolver) }
  let(:resolver) do
    described_class.new(
      dependency_files: project_dependency_files("javascript/no_lockfile"), credentials: []
    )
  end

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_yarn_berry_conflicting_dependencies).and_return(true)
    allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_return([])
  end

  it "passes the installed version to the conflict helper when enabled" do
    expect(resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")).to be_empty
    expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).with(
      command: Dependabot::Bun::NativeHelpers.helper_path,
      function: "yarn:findConflictingDependencies",
      args: [a_kind_of(String), "brace-expansion", "2.1.4", "2.1.2"]
    )
  end

  context "when the experiment is disabled" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_yarn_berry_conflicting_dependencies).and_return(false)
    end

    it "passes the original unscoped arguments to the conflict helper" do
      expect(resolver.conflicting_dependencies(dependency: dependency, target_version: "2.1.4")).to be_empty
      expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess)
        .with(
          command: Dependabot::Bun::NativeHelpers.helper_path,
          function: "yarn:findConflictingDependencies",
          args: [a_kind_of(String), "brace-expansion", "2.1.4"]
        )
    end
  end
end
