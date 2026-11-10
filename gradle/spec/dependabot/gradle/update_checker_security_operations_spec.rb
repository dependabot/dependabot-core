# typed: strict
# frozen_string_literal: true

require "spec_helper"

$LOAD_PATH << File.expand_path("../dependabot-updater/lib", common_dir)

require "dependabot/gradle"
require "dependabot/job"
require "dependabot/dependency_snapshot"
require "dependabot/dependency_change_builder"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/create_security_update_pull_request"
require "dependabot/updater/operations/create_group_update_pull_request"
require "dependabot/updater/operations/refresh_security_update_pull_request"

RSpec.describe Dependabot::Gradle::UpdateChecker do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Keep Sorbet signatures attached to their declarations.
  sig { returns(String) }
  let(:project_path) { File.expand_path("../../fixtures/projects/transitive_security", __dir__) }

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:files) do
    %w(build.gradle settings.gradle gradle.lockfile).map do |name|
      Dependabot::DependencyFile.new(name: name, content: File.read(File.join(project_path, name)))
    end
  end

  sig { returns(Dependabot::Job) }
  let(:job) do
    Dependabot::Job.new_update_job(
      job_id: "gradle-transitive",
      repo_contents_path: project_path,
      job_definition: {
        "job" => {
          "package-manager" => "gradle",
          "allowed-updates" => [{ "dependency-type" => "direct", "update-type" => "all" }],
          "dependencies" => ["org.example:child"],
          "existing-pull-requests" => [],
          "ignore-conditions" => [],
          "lockfile-only" => false,
          "requirements-update-strategy" => nil,
          "security-updates-only" => true,
          "update-subdependencies" => false,
          "updating-a-pull-request" => false,
          "source" => { "provider" => "github", "repo" => "example/gradle", "directory" => "/" },
          "security-advisories" => [{
            "dependency-name" => "org.example:child",
            "affected-versions" => ["[1.0,1.1)"],
            "patched-versions" => [],
            "unaffected-versions" => []
          }]
        }
      }
    )
  end

  sig { returns(Dependabot::DependencySnapshot) }
  let(:snapshot) do
    Dependabot::DependencySnapshot.create_from_job_definition(
      job: job,
      fetched_files: Dependabot::FetchedFiles.new(base_commit_sha: "test-sha", dependency_files: files)
    )
  end

  sig { returns(Dependabot::Service) }
  let(:service) do
    instance_double(
      Dependabot::Service,
      increment_metric: nil,
      record_update_job_error: nil,
      create_pull_request: nil,
      update_pull_request: nil,
      close_pull_request: nil,
      record_ecosystem_meta: nil,
      record_cooldown_meta: nil
    )
  end

  sig { returns(Dependabot::Updater::ErrorHandler) }
  let(:error_handler) { instance_double(Dependabot::Updater::ErrorHandler) }
  # rubocop:enable RSpec/ScatteredLet

  before do
    Dependabot::Experiments.register(:gradle_transitive_security_updates, true)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
    stub_request(:get, "https://repo.maven.apache.org/maven2/org/example/child/maven-metadata.xml")
      .to_return(body: <<~XML)
        <metadata><versioning><versions><version>1.0</version><version>1.1</version></versions></versioning></metadata>
      XML
  end

  sig { void }
  def perform_update
    Dependabot::Updater::Operations::CreateSecurityUpdatePullRequest.new(
      service: service, job: job, dependency_snapshot: snapshot, error_handler: error_handler
    ).perform
  end

  it "submits a security PR containing only the updated lockfile" do
    expect(service).to receive(:create_pull_request) do |change, sha|
      expect(sha).to eq("test-sha")
      expect(change.updated_dependencies.map(&:version)).to eq(["1.1"])
      expect(change.updated_dependency_files.map(&:name)).to eq(["gradle.lockfile"])
      expect(change.updated_dependency_files.first.content).to include("org.example:child:1.1=")
    end
    perform_update
    expect(service).not_to have_received(:record_update_job_error)
  end

  it "finds a vulnerable version even when another subproject locks a lower safe version" do
    files << Dependabot::DependencyFile.new(
      name: "app/gradle.lockfile", content: "org.example:child:0.9=runtimeClasspath\n"
    )
    expect(service).to receive(:create_pull_request) do |change, _sha|
      expect(change.updated_dependencies.map(&:previous_version)).to eq(["1.0"])
      expect(change.updated_dependency_files.map(&:name)).to contain_exactly("gradle.lockfile", "app/gradle.lockfile")
    end
    perform_update
    expect(service).not_to have_received(:record_update_job_error)
  end

  context "when the lowest locked version is safe" do
    before do
      files << Dependabot::DependencyFile.new(
        name: "app/gradle.lockfile", content: "org.example:child:0.9=runtimeClasspath\n"
      )
    end

    it "creates a grouped security update for the higher vulnerable version" do
      allow(Dependabot::Workspace).to receive(:setup)
      group = Dependabot::DependencyGroup.new(name: "security", rules: { "patterns" => ["org.example:child"] })
      group.dependencies.concat(snapshot.job_dependencies)
      expect(service).to receive(:create_pull_request) do |change, _sha|
        expect(change.updated_dependencies.map(&:previous_version)).to eq(["1.0"])
        expect(change.updated_dependencies.map(&:version)).to eq(["1.1"])
        expect(change.updated_dependency_files.map(&:name)).to contain_exactly("gradle.lockfile", "app/gradle.lockfile")
      end
      Dependabot::Updater::Operations::CreateGroupUpdatePullRequest.new(
        service: service, job: job, dependency_snapshot: snapshot, error_handler: error_handler, group: group
      ).perform
      expect(service).not_to have_received(:record_update_job_error)
    end

    it "refreshes an existing security update instead of closing it" do
      job.existing_pull_requests << Dependabot::PullRequest.new(
        [Dependabot::PullRequest::Dependency.new(name: "org.example:child", version: "1.1")]
      )
      expect(service).to receive(:update_pull_request) do |change, _sha|
        expect(change.updated_dependencies.map(&:version)).to eq(["1.1"])
        expect(change.updated_dependency_files.map(&:name)).to contain_exactly("gradle.lockfile", "app/gradle.lockfile")
      end
      Dependabot::Updater::Operations::RefreshSecurityUpdatePullRequest.new(
        service: service, job: job, dependency_snapshot: snapshot, error_handler: error_handler
      ).perform
      expect(service).not_to have_received(:close_pull_request)
    end
  end

  it "reports an unresolvable lockfile as a security update that is not possible" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .and_raise(Dependabot::DependencyFileNotResolvable, "A strict parent constraint blocks the update")
    perform_update
    expect(service).not_to have_received(:create_pull_request)
    expect(service).to have_received(:record_update_job_error).with(
      hash_including(error_type: "security_update_not_possible")
    )
  end

  it "reports a stale alert as not needing an update when the locked version is already safe" do
    lockfile = T.must(files.find { |file| file.name == "gradle.lockfile" })
    lockfile.content = T.must(lockfile.content).sub("org.example:child:1.0=", "org.example:child:1.1=")
    perform_update
    expect(service).not_to have_received(:create_pull_request)
    expect(service).to have_received(:record_update_job_error).with(
      hash_including(error_type: "security_update_not_needed")
    )
    expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
  end

  it "preserves the original dependency-not-found behavior with the experiment disabled" do
    Dependabot::Experiments.register(:gradle_transitive_security_updates, false)
    perform_update
    expect(service).not_to have_received(:create_pull_request)
    expect(service).to have_received(:record_update_job_error).with(
      hash_including(error_type: "security_update_dependency_not_found")
    )
  end
end
