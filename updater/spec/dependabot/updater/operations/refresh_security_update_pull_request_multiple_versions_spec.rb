# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/fetched_files"
require "dependabot/dependency_snapshot"
require "dependabot/dependency_change_builder"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/refresh_security_update_pull_request"
require "dependabot/npm_and_yarn"

# Sorbet fixture signatures must stay beside their lets.
# rubocop:disable-next RSpec/ScatteredLet
RSpec.describe Dependabot::Updater::Operations::RefreshSecurityUpdatePullRequest do
  extend T::Sig

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) do
    fixture_path = File.join(
      Gem::Specification.find_by_name("dependabot-npm_and_yarn").gem_dir,
      "spec/fixtures/projects/yarn_berry/multiple_brace_expansion_versions"
    )
    %w(package.json yarn.lock).map do |name|
      Dependabot::DependencyFile.new(name: name, content: File.read(File.join(fixture_path, name)))
    end
  end

  sig { returns(Dependabot::Job) }
  let(:job) do
    definition = job_definition_fixture("bundler/version_updates/pull_request_simple")
    definition["job"].merge!(
      "package-manager" => "npm_and_yarn",
      "allowed-updates" => [{ "dependency-type" => "all", "update-type" => "security" }],
      "dependencies" => ["brace-expansion"],
      "security-updates-only" => true,
      "updating-a-pull-request" => true,
      "existing-pull-requests" => [],
      "security-advisories" => [{
        "dependency-name" => "brace-expansion",
        "affected-versions" => [">= 2.0.0 < 2.1.4"],
        "patched-versions" => [],
        "unaffected-versions" => []
      }]
    )
    Dependabot::Job.new_update_job(job_id: "123", job_definition: definition)
  end

  sig { returns(Dependabot::DependencySnapshot) }
  let(:snapshot) do
    Dependabot::DependencySnapshot.create_from_job_definition(
      job: job,
      fetched_files: Dependabot::FetchedFiles.new(base_commit_sha: "mock-sha", dependency_files: dependency_files)
    )
  end

  sig { returns(RSpec::Mocks::InstanceVerifyingDouble) }
  let(:service) do
    instance_double(Dependabot::Service, record_ecosystem_meta: nil, increment_metric: nil)
  end

  sig { returns(RSpec::Mocks::InstanceVerifyingDouble) }
  let(:error_handler) { instance_double(Dependabot::Updater::ErrorHandler) }

  before do
    allow(Dependabot::Experiments).to receive(:enabled?).and_return(false)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_yarn_berry_conflicting_dependencies).and_return(true)
    allow(Dependabot::NpmAndYarn::Helpers).to receive_messages(
      yarn_major_version: 4,
      yarn_berry_supports_minimal_age_gate?: true
    )
    allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command) do
      lockfile = T.must(dependency_files.find { |file| file.name == "yarn.lock" })
      manifest = JSON.parse(File.read("package.json"))
      version = manifest.fetch("resolutions", {})["brace-expansion@npm:^2.0.2"]
      File.write("yarn.lock", T.must(lockfile.content).gsub("2.1.2", "2.1.4")) if version == "npm:2.1.4"
      ""
    end

    versions = %w(1.1.12 1.1.18 2.1.2 2.1.4 5.0.2 5.0.12)
    registry = {
      "name" => "brace-expansion",
      "dist-tags" => { "latest" => "5.0.12" },
      "versions" => versions.to_h do |version|
        [version, {
          "name" => "brace-expansion",
          "version" => version,
          "dist" => { "tarball" => "https://registry.npmjs.org/brace-expansion/-/brace-expansion-#{version}.tgz" }
        }]
      end
    }
    stub_request(:get, "https://registry.npmjs.org/brace-expansion")
      .to_return(status: 200, body: registry.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:head, %r{\Ahttps://registry\.npmjs\.org/brace-expansion/-/brace-expansion-[\d.]+\.tgz\z})
      .to_return(status: 200)
  end

  it "refreshes the vulnerable installed version and preserves safe versions" do
    expect(snapshot.job_dependencies.first).to have_attributes(version: "1.1.12")
    expect(error_handler).not_to receive(:handle_dependency_error)
    expect(service).to receive(:create_pull_request) do |change, base_commit_sha|
      expect(base_commit_sha).to eq("mock-sha")
      expect(change.updated_dependencies).to contain_exactly(
        have_attributes(name: "brace-expansion", previous_version: "2.1.2", version: "2.1.4")
      )
      lockfile = change.updated_dependency_files.find { |file| file.name == "yarn.lock" }
      expect(lockfile.content).to include(
        'resolution: "brace-expansion@npm:1.1.12"',
        'resolution: "brace-expansion@npm:2.1.4"',
        'resolution: "brace-expansion@npm:5.0.2"'
      )
      expect(lockfile.content).not_to include('resolution: "brace-expansion@npm:2.1.2"')
    end

    described_class.new(service: service, job: job, dependency_snapshot: snapshot, error_handler: error_handler).perform
  end
end
