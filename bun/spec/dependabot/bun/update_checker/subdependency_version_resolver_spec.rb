# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/update_checker/subdependency_version_resolver"

RSpec.describe Dependabot::Bun::UpdateChecker::SubdependencyVersionResolver do
  subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "@dependabot-fixtures/npm-transitive-dependency",
      version: "1.0.0",
      requirements: [],
      package_manager: "bun"
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
    [Dependabot::DependencyFile.new(name: "bun.lock", content: "{}", directory: ".")]
  end
  let(:latest_allowable_version) { Dependabot::Bun::Version.new("1.0.1") }
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
    instance_double(Dependabot::Bun::UpdateChecker::DependencyFilesBuilder)
  end

  before do
    allow(resolver).to receive_messages(
      dependency_files_builder: dependency_files_builder,
      filtered_lockfiles: dependency_files,
      version_from_updated_lockfiles: Gem::Version.new("1.0.1")
    )
    allow(dependency_files_builder).to receive(:write_temporary_dependency_files) do
      File.write("bun.lock", "dummy lockfile")
    end

    allow(Dependabot::Bun::Helpers).to receive(:run_bun_command)
  end

  it "runs bun update with --ignore-scripts for subdependency lockfile updates" do
    expect(latest_resolvable_version).to eq(Gem::Version.new("1.0.1"))

    expect(Dependabot::Bun::Helpers).to have_received(:run_bun_command).with(
      "update @dependabot-fixtures/npm-transitive-dependency --save-text-lockfile --ignore-scripts",
      fingerprint: "update <dependency_name> --save-text-lockfile --ignore-scripts"
    )
  end
end
