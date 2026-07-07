# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nub/update_checker/subdependency_version_resolver"

RSpec.describe Dependabot::Nub::UpdateChecker::SubdependencyVersionResolver do
  subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "@dependabot-fixtures/npm-transitive-dependency",
      version: "1.0.0",
      requirements: [],
      package_manager: "nub"
    )
  end
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com"
      }
    )]
  end
  let(:dependency_files) do
    [Dependabot::DependencyFile.new(name: "nub.lock", content: "{}", directory: ".")]
  end
  let(:latest_allowable_version) { Dependabot::Nub::Version.new("1.0.1") }
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      dependency_files: dependency_files,
      ignored_versions: [],
      latest_allowable_version: latest_allowable_version,
      repo_contents_path: nil
    )
  end
  let(:dependency_files_builder) do
    instance_double(Dependabot::Nub::UpdateChecker::DependencyFilesBuilder)
  end

  before do
    allow(resolver).to receive_messages(
      dependency_files_builder: dependency_files_builder,
      filtered_lockfiles: dependency_files,
      version_from_updated_lockfiles: Gem::Version.new("1.0.1")
    )
    allow(dependency_files_builder).to receive(:write_temporary_dependency_files) do
      File.write("nub.lock", "dummy lockfile")
    end

    allow(Dependabot::Nub::Helpers).to receive(:run_nub_command)
  end

  it "runs nub update with --ignore-scripts for subdependency lockfile updates" do
    expect(latest_resolvable_version).to eq(Gem::Version.new("1.0.1"))

    expect(Dependabot::Nub::Helpers).to have_received(:run_nub_command).with(
      "update @dependabot-fixtures/npm-transitive-dependency --lockfile-only --ignore-scripts",
      fingerprint: "update <dependency_name> --lockfile-only --ignore-scripts"
    )
  end
end
