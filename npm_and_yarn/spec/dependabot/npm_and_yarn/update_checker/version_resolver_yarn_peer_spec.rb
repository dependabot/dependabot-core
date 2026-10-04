# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/npm_and_yarn/update_checker/version_resolver"

RSpec.describe Dependabot::NpmAndYarn::UpdateChecker::VersionResolver do
  subject(:resolved_version) { resolver.latest_resolvable_version }

  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: project_dependency_files("yarn_berry/peer_dependency"),
      credentials: [],
      latest_allowable_version: "16.3.1",
      latest_version_finder: finder,
      repo_contents_path: nil
    )
  end
  let(:finder) { instance_double(Dependabot::NpmAndYarn::UpdateChecker::PackageLatestVersionFinder, possible_releases: []) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "react-dom",
      version: "15.2.0",
      package_manager: "npm_and_yarn",
      requirements: [{ file: "package.json", requirement: "^15.2.0", groups: ["dependencies"], source: nil }]
    )
  end

  before do
    allow(Dependabot::NpmAndYarn::Helpers).to receive(:yarn_major_version).and_return(4)
    allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command) do |command|
      command.start_with?("add react-dom@16.3.1 ") ? peer_warning : ""
    end
  end

  context "when Yarn puts the peer identifier after the provided version" do
    let(:peer_warning) do
      "YN0060: │ react is listed by your project with version 15.2.0 (p89012), " \
        "which doesn't satisfy what react-dom requests (^16.0.0)."
    end

    it "rejects a candidate whose peer requirements are unsatisfied" do
      expect(resolved_version).to be_nil
    end
  end

  context "when older Yarn puts the peer identifier after the requesting dependency" do
    let(:peer_warning) do
      "YN0060: │ react is listed by your project with version 15.2.0, " \
        "which doesn't satisfy what react-dom (p89012) requests (^16.0.0)."
    end

    it "rejects a candidate whose peer requirements are unsatisfied" do
      expect(resolved_version).to be_nil
    end
  end
end
