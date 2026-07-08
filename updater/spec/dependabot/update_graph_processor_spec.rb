# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dependency_file_helpers"

require "dependabot/bundler"

require "dependabot/service"
require "dependabot/update_graph_processor"

RSpec.describe Dependabot::UpdateGraphProcessor do
  subject(:update_graph_processor) do
    described_class.new(
      service:,
      job:,
      base_commit_sha:,
      dependency_files:,
      directory_fetch_errors:
    )
  end

  let(:service) do
    instance_double(
      Dependabot::Service,
      create_dependency_submission: nil,
      record_update_job_error: nil,
      record_update_job_warning: nil,
      record_workflow_result: nil
    )
  end

  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  let(:repo) { "dependabot-fixtures/dependabot-test-ruby-package" }
  let(:branch) { "develop" }
  let(:provider) { "github" }

  let(:source) do
    Dependabot::Source.new(
      provider: provider,
      repo: repo,
      directories: directories,
      branch: branch
    )
  end

  let(:job) do
    instance_double(
      Dependabot::Job,
      id: "42",
      package_manager: "bundler",
      repo_contents_path: repo_contents_path,
      credentials: credentials,
      source: source,
      reject_external_code?: false,
      experiments: { large_hadron_collider: true }
    )
  end

  let(:base_commit_sha) { "fake-sha" }
  let(:repo_contents_path) { nil }
  let(:directory_fetch_errors) { {} }

  context "with a basic Gemfile project" do
    let(:directories) { [directory] }
    let(:directory) { "/" }
    let(:repo_contents_path) { build_tmp_repo("bundler/original", path: "") }

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: directory
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: directory
        )
      ]
    end

    it "emits the expected payload to the Dependabot service" do
      expect(service).to receive(:create_dependency_submission) do |args|
        expect(args[:dependency_submission]).to be_a(GithubApi::DependencySubmission)

        payload = args[:dependency_submission].payload

        # Job references are as expected
        expect(payload[:job][:correlator]).to eq("dependabot-bundler")
        expect(payload[:job][:id]).to eq("42")

        # Git references are as expected
        expect(payload[:sha]).to eq(base_commit_sha)
        expect(payload[:ref]).to eql("refs/heads/#{branch}")

        # Manifest information is as expected
        expect(payload[:manifests].length).to eq(1)

        # Lockfile data is correct
        lockfile = payload[:manifests].fetch("/Gemfile.lock")
        expect(lockfile[:name]).to eq("/Gemfile.lock")
        expect(lockfile[:file][:source_location]).to eq("Gemfile.lock")

        # Resolved dependencies are correct
        expect(lockfile[:resolved].length).to eq(2)

        dependency1 = lockfile[:resolved]["pkg:gem/dummy-pkg-a@2.0.0"]
        expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a@2.0.0")

        dependency2 = lockfile[:resolved]["pkg:gem/dummy-pkg-b@1.1.0"]
        expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b@1.1.0")
      end

      update_graph_processor.run
    end

    it "records a workflow result for the directory" do
      expect(service).to receive(:record_workflow_result).with(
        directory: "/",
        status: "ok",
        details: "Found 2 dependencies"
      )

      update_graph_processor.run
    end
  end

  context "with a small sinatra app" do
    let(:directories) { [directory] }
    let(:directory) { "/" }
    let(:repo_contents_path) { build_tmp_repo("bundler_sinatra_app/original", path: "") }

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler_sinatra_app/original/Gemfile"),
          directory: directory
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler_sinatra_app/original/Gemfile.lock"),
          directory: directory
        )
      ]
    end

    it "emits the expected payload to the Dependabot service" do
      expect(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload

        # Manifest information is as expected
        expect(payload[:manifests].length).to eq(1)
        lockfile = payload[:manifests].fetch("/Gemfile.lock")

        # Resolved dependencies are correct:
        expect(lockfile[:resolved].length).to eq(28)

        # the lockfile should be reporting 4 direct dependencies and 24 indirect ones
        expect(lockfile[:resolved].values.count { |dep| dep[:relationship] == "direct" }).to eq(4)
        expect(lockfile[:resolved].values.count { |dep| dep[:relationship] == "indirect" }).to eq(24)

        # the following top-level packages should be defined in the right groups
        {
          "sinatra" => "4.1.1",
          "pry" => "0.15.2",
          "rspec" => "3.13.1",
          "capybara" => "3.40.0"
        }.each do |pkg_name, version|
          key = "pkg:gem/#{pkg_name}@#{version}"
          resolved_dep = lockfile[:resolved][key]

          expect(resolved_dep).not_to be_empty
          expect(resolved_dep[:relationship]).to eq("direct")

          case pkg_name
          when "sinatra"
            expect(resolved_dep[:package_url]).to eql("pkg:gem/sinatra@4.1.1")
            expect(resolved_dep[:scope]).to eq("runtime")
          when "pry"
            expect(resolved_dep[:package_url]).to eql("pkg:gem/pry@0.15.2")
            expect(resolved_dep[:scope]).to eq("development")
          when "rspec"
            expect(resolved_dep[:package_url]).to eql("pkg:gem/rspec@3.13.1")
            expect(resolved_dep[:scope]).to eq("development")
          when "capybara"
            expect(resolved_dep[:package_url]).to eql("pkg:gem/capybara@3.40.0")
            expect(resolved_dep[:scope]).to eq("development")
          end
        end

        # the direct ones were verified above.
        # let's pull out a few indirect dependencies to check
        rack = lockfile[:resolved]["pkg:gem/rack@3.1.16"]
        expect(rack[:package_url]).to eql("pkg:gem/rack@3.1.16")
        expect(rack[:relationship]).to eq("indirect")
        expect(rack[:scope]).to eq("runtime")

        addressable = lockfile[:resolved]["pkg:gem/addressable@2.8.7"]
        expect(addressable[:package_url]).to eql("pkg:gem/addressable@2.8.7")
        expect(addressable[:relationship]).to eq("indirect")
        expect(addressable[:scope]).to eq("development")
      end

      update_graph_processor.run
    end
  end

  context "with a job that specifies multiple directories" do
    let(:directories) { [dir1, dir2] }

    let(:dir1) { "/" }
    let(:dir2) { "/subproject/" }
    let(:repo_contents_path) { build_tmp_repo("bundler_sinatra_app/original", path: "") }

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler_sinatra_app/original/Gemfile"),
          directory: dir1
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler_sinatra_app/original/Gemfile.lock"),
          directory: dir1
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: dir2
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: dir2
        )
      ]
    end

    it "emits a snapshot for each directory" do
      expect(service).to receive(:create_dependency_submission).twice

      update_graph_processor.run
    end

    it "correctly snapshots the first directory" do
      payload = nil

      # Capture the first call
      expect(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload
      end
      expect(service).to receive(:create_dependency_submission).once

      update_graph_processor.run

      expect(payload).not_to be_nil
      expect(payload[:job][:correlator]).to eql("dependabot-bundler")

      # Check we have a Sinatra app with 28 dependencies
      expect(payload[:manifests].length).to eq(1)
      lockfile = payload[:manifests].fetch("/Gemfile.lock")

      expect(lockfile[:resolved].length).to eq(28)

      expect(lockfile[:resolved].values.count { |dep| dep[:relationship] == "direct" }).to eq(4)
      expect(lockfile[:resolved].values.count { |dep| dep[:relationship] == "indirect" }).to eq(24)
    end

    it "correctly snapshots the second directory" do
      payload = nil

      expect(service).to receive(:create_dependency_submission).once
      # Capture the second call
      expect(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload
      end

      update_graph_processor.run

      expect(payload).not_to be_nil
      expect(payload[:job][:correlator]).to eql("dependabot-bundler-subproject")

      # Check we have the simple app with 2 dependencies
      expect(payload[:manifests].length).to eq(1)
      lockfile = payload[:manifests].fetch("/subproject/Gemfile.lock")

      expect(lockfile[:resolved].length).to eq(2)

      dependency1 = lockfile[:resolved]["pkg:gem/dummy-pkg-a@2.0.0"]
      expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a@2.0.0")
      dependency2 = lockfile[:resolved]["pkg:gem/dummy-pkg-b@1.1.0"]
      expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b@1.1.0")
    end

    context "when the first directory fails to process" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "Gemfile",
            content: "garbage",
            directory: dir1
          ),
          Dependabot::DependencyFile.new(
            name: "Gemfile.lock",
            content: "garbage in greater volume",
            directory: dir1
          ),
          Dependabot::DependencyFile.new(
            name: "Gemfile",
            content: fixture("bundler/original/Gemfile"),
            directory: dir2
          ),
          Dependabot::DependencyFile.new(
            name: "Gemfile.lock",
            content: fixture("bundler/original/Gemfile.lock"),
            directory: dir2
          )
        ]
      end

      context "when executing standalone" do
        before do
          allow(Dependabot::Environment).to receive(:github_actions?).and_return(false)
        end

        it "emits a snapshot and an error" do
          expect(service).to receive(:create_dependency_submission).once
          expect(service).to receive(:record_update_job_error).once

          update_graph_processor.run
        end

        it "correctly snapshots the second directory" do
          payload = nil

          expect(service).to receive(:create_dependency_submission) do |args|
            payload = args[:dependency_submission].payload
          end

          update_graph_processor.run

          expect(payload).not_to be_nil
          expect(payload[:job][:correlator]).to eql("dependabot-bundler-subproject")

          # Check we have the simple app with 2 dependencies
          expect(payload[:manifests].length).to eq(1)
          lockfile = payload[:manifests].fetch("/subproject/Gemfile.lock")

          expect(lockfile[:resolved].length).to eq(2)

          dependency1 = lockfile[:resolved]["pkg:gem/dummy-pkg-a@2.0.0"]
          expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a@2.0.0")
          dependency2 = lockfile[:resolved]["pkg:gem/dummy-pkg-b@1.1.0"]
          expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b@1.1.0")
        end
      end

      context "when executing in GitHub Actions" do
        before do
          allow(Dependabot::Environment).to receive(:github_actions?).and_return(true)
        end

        it "emits a blank snapshot, a normal snapshot and an error" do
          expect(service).to receive(:create_dependency_submission).twice
          expect(service).to receive(:record_update_job_error).once

          update_graph_processor.run
        end

        it "emits a blank snapshot for the first directory" do
          payload = nil

          # Capture the first call
          expect(service).to receive(:create_dependency_submission) do |args|
            payload = args[:dependency_submission].payload
          end
          expect(service).to receive(:create_dependency_submission).once

          update_graph_processor.run

          expect(payload).not_to be_nil
          expect(payload[:job][:correlator]).to eql("dependabot-bundler")

          # It should be empty
          expect(payload[:manifests].length).to be_zero

          # It should contain the expected metadata
          expect(payload[:metadata][:status]).to eql(GithubApi::DependencySubmission::SnapshotStatus::FAILED.serialize)
          expect(payload[:metadata][:reason]).to eql("dependency_file_not_evaluatable")
          expect(payload[:metadata][:scanned_manifest_path]).to eql("rubygems::/")
        end

        it "correctly snapshots the second directory" do
          payload = nil

          # Capture the second call
          expect(service).to receive(:create_dependency_submission).once
          expect(service).to receive(:create_dependency_submission) do |args|
            payload = args[:dependency_submission].payload
          end

          update_graph_processor.run

          expect(payload).not_to be_nil
          expect(payload[:job][:correlator]).to eql("dependabot-bundler-subproject")

          # Check we have the simple app with 2 dependencies
          expect(payload[:manifests].length).to eq(1)
          lockfile = payload[:manifests].fetch("/subproject/Gemfile.lock")

          expect(lockfile[:resolved].length).to eq(2)

          dependency1 = lockfile[:resolved]["pkg:gem/dummy-pkg-a@2.0.0"]
          expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a@2.0.0")
          dependency2 = lockfile[:resolved]["pkg:gem/dummy-pkg-b@1.1.0"]
          expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b@1.1.0")

          # We should have metadata indicating a successful snapshot
          expect(payload[:metadata][:status]).to eql(GithubApi::DependencySubmission::SnapshotStatus::SUCCESS.serialize)
          expect(payload[:metadata][:reason]).to be_nil
          expect(payload[:metadata][:scanned_manifest_path]).to eql("rubygems::/subproject/")
        end
      end
    end
  end

  context "with vendored files" do
    let(:directories) { [directory] }
    let(:directory) { "/" }
    let(:repo_contents_path) { build_tmp_repo("bundler_vendored/original", path: "") }

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: directory
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: directory
        ),
        Dependabot::DependencyFile.new(
          name: "vendor/ruby/3.4.0/cache/addressable-2.8.7.gem",
          content: "stuff",
          directory: directory,
          support_file: true,
          vendored_file: true
        )
      ]
    end

    it "they are not mentioned in the dependency submission payload" do
      expect(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload

        # We only expect a lockfile to be returned
        expect(payload[:manifests].length).to eq(1)
        expect(payload[:manifests].keys).to eq(%w(/Gemfile.lock))
      end

      update_graph_processor.run
    end
  end

  context "without a Gemfile.lock" do
    let(:directories) { [directory] }
    let(:directory) { "/" }
    let(:repo_contents_path) { build_tmp_repo("bundler/original", path: "") }

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: directory
        )
      ]
    end

    it "submits only the Gemfile" do
      expect(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload

        # We only expect a Gemfile to be returned
        expect(payload[:manifests].length).to eq(1)

        # Gemfile data is correct
        gemfile = payload[:manifests].fetch("/Gemfile")
        expect(gemfile[:name]).to eq("/Gemfile")
        expect(gemfile[:file][:source_location]).to eq("Gemfile")

        # Resolved dependencies are correct
        expect(gemfile[:resolved].length).to eq(2)

        dependency1 = gemfile[:resolved]["pkg:gem/dummy-pkg-a"]
        expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a")

        dependency2 = gemfile[:resolved]["pkg:gem/dummy-pkg-b"]
        expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b")
      end

      update_graph_processor.run
    end
  end

  # A manifest file that resolves to no dependencies should still be reported so the snapshot
  # records that the file was scanned, rather than being omitted from the manifest list.
  context "with a set of dependency files that resolve to no dependencies" do
    let(:directories) { [directory] }
    let(:directory) { "/" }
    let(:repo_contents_path) { build_tmp_repo("bundler/original", path: "") }

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: "",
          directory: directory
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: "",
          directory: directory
        )
      ]
    end

    it "generates a snapshot reporting the manifest with an empty resolved collection" do
      expect(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload

        expect(payload[:job][:correlator]).to eq("dependabot-bundler")

        # The manifest is still reported, with no resolved dependencies
        expect(payload[:manifests].length).to eq(1)

        manifest = payload[:manifests].fetch("/Gemfile.lock")
        expect(manifest[:name]).to eq("/Gemfile.lock")
        expect(manifest[:resolved]).to be_empty

        # The snapshot is a successful scan
        expect(payload[:metadata][:status]).to eq(GithubApi::DependencySubmission::SnapshotStatus::SUCCESS.serialize)
        expect(payload[:metadata][:scanned_manifest_path]).to eql("rubygems::/")
      end

      update_graph_processor.run
    end
  end

  # This is expected for graph updates corresponding to deleted files
  context "with non-existent dependency files" do
    let(:directories) { [directory] }
    let(:directory) { "/" }
    let(:repo_contents_path) { build_tmp_repo("bundler/original", path: "") }

    let(:dependency_files) do
      []
    end

    it "generates an empty snapshot with metadata" do
      expect(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload

        expect(payload[:job][:correlator]).to eq("dependabot-bundler")
        expect(payload[:manifests]).to be_empty

        # It should contain the expected metadata
        expect(payload[:metadata][:status]).to eq(GithubApi::DependencySubmission::SnapshotStatus::SKIPPED.serialize)
        expect(payload[:metadata][:reason]).to eq(GithubApi::DependencySubmission::EMPTY_REASON_NO_MANIFESTS)
        expect(payload[:metadata][:scanned_manifest_path]).to eql("rubygems::/")
      end

      update_graph_processor.run
    end
  end

  context "with a directory that failed to fetch due to an unreachable path dependency" do
    let(:directories) { [dir_ok, dir_broken] }
    let(:dir_ok) { "/" }
    let(:dir_broken) { "/broken" }
    let(:repo_contents_path) { build_tmp_repo("bundler/original", path: "") }

    let(:directory_fetch_errors) do
      { dir_broken => Dependabot::PathDependenciesNotReachable.new(["./local"]) }
    end

    # The other directory has no manifests so it is reported without needing to
    # parse an ecosystem, keeping the focus on the skipped-fetch behaviour.
    let(:dependency_files) { [] }

    it "submits a skipped snapshot describing the unreachable path dependency" do
      submissions = []
      allow(service).to receive(:create_dependency_submission) do |args|
        submissions << args[:dependency_submission]
      end

      update_graph_processor.run

      skipped = submissions.find do |s|
        s.payload[:metadata][:scanned_manifest_path] == "rubygems::/broken"
      end

      expect(skipped).not_to be_nil
      expect(skipped.payload[:metadata][:status])
        .to eq(GithubApi::DependencySubmission::SnapshotStatus::SKIPPED.serialize)
      expect(skipped.payload[:metadata][:reason])
        .to eq(GithubApi::DependencySubmission::SKIPPED_REASON_PATH_DEPENDENCIES_NOT_REACHABLE)
      expect(skipped.payload[:manifests]).to be_empty
    end

    it "does not mislabel the affected directory as having no manifests" do
      allow(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload
        if payload[:metadata][:scanned_manifest_path] == "rubygems::/broken"
          expect(payload[:metadata][:status])
            .to eq(GithubApi::DependencySubmission::SnapshotStatus::SKIPPED.serialize)
          expect(payload[:metadata][:reason])
            .not_to eq(GithubApi::DependencySubmission::EMPTY_REASON_NO_MANIFESTS)
        end
      end

      update_graph_processor.run
    end

    it "records a skipped workflow result for the affected directory" do
      allow(service).to receive(:record_workflow_result)
      expect(service).to receive(:record_workflow_result).with(
        directory: dir_broken,
        status: GithubApi::DependencySubmission::SnapshotStatus::SKIPPED.serialize,
        details: GithubApi::DependencySubmission::SKIPPED_REASON_PATH_DEPENDENCIES_NOT_REACHABLE
      )

      update_graph_processor.run
    end

    it "does not abort the job: the other directory is still processed" do
      submissions = []
      allow(service).to receive(:create_dependency_submission) do |args|
        submissions << args[:dependency_submission].payload
      end

      update_graph_processor.run

      scanned_paths = submissions.map { |p| p[:metadata][:scanned_manifest_path] }
      expect(scanned_paths).to include("rubygems::/", "rubygems::/broken")
    end

    it "records a warning about the incomplete graph" do
      expect(service).to receive(:record_update_job_warning).with(
        hash_including(warn_type: "dependency_graph_incomplete")
      )

      update_graph_processor.run
    end
  end

  context "with non-existent dependency files in a subpath" do
    let(:directories) { [directory] }
    let(:directory) { "/subproject/" }
    let(:repo_contents_path) { build_tmp_repo("bundler/original", path: "") }

    let(:dependency_files) do
      []
    end

    it "generates an empty snapshot with metadata" do
      expect(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload

        expect(payload[:job][:correlator]).to eq("dependabot-bundler-subproject")
        expect(payload[:manifests]).to be_empty

        # It should contain the expected metadata
        expect(payload[:metadata][:status]).to eq(GithubApi::DependencySubmission::SnapshotStatus::SKIPPED.serialize)
        expect(payload[:metadata][:reason]).to eq(GithubApi::DependencySubmission::EMPTY_REASON_NO_MANIFESTS)
        expect(payload[:metadata][:scanned_manifest_path]).to eql("rubygems::/subproject/")
      end

      update_graph_processor.run
    end
  end

  describe "job validation" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: "/"
        )
      ]
    end

    context "when the source has no directories defined" do
      let(:directories) { nil }

      it "raises an error" do
        expect { update_graph_processor.run }.to raise_error(Dependabot::DependabotError)
      end
    end

    context "when the source directories are empty" do
      let(:directories) { [] }

      it "raises an error" do
        expect { update_graph_processor.run }.to raise_error(Dependabot::DependabotError)
      end
    end

    context "when the source does not specify a branch" do
      let(:directories) { ["/"] }
      let(:branch) { nil }
      let(:repo_contents_path) { build_tmp_repo("bundler/original", path: "") }

      it "retrieves the default branch via Git" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("origin/very-esoteric-naming\n")

        expect(service).to receive(:create_dependency_submission) do |args|
          payload = args[:dependency_submission].payload

          expect(payload[:ref]).to eql("refs/heads/very-esoteric-naming")
        end

        update_graph_processor.run
      end
    end
  end

  context "when fetching subdependencies fails" do
    let(:directories) { [directory] }
    let(:directory) { "/" }
    let(:repo_contents_path) { build_tmp_repo("bundler/original", path: "") }

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: directory
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: directory
        )
      ]
    end

    context "when the error is a known type" do
      before do
        original_grapher_class = Dependabot::DependencyGraphers.for_package_manager(job.package_manager)

        failing_grapher_class = Class.new(original_grapher_class) do
          def initialize(file_parser:)
            super
            @raise_once = true
          end

          def fetch_subdependencies(_dependency)
            if @raise_once
              @raise_once = false
              raise Dependabot::GitDependenciesNotReachable, "github.com/dependabot/cli", "boom"
            end
            []
          end
        end

        allow(Dependabot::DependencyGraphers).to receive(:for_package_manager)
          .with(job.package_manager).and_return(failing_grapher_class)
      end

      it "records a warning and still submits a dependency submission" do
        expect(service).to receive(:create_dependency_submission) do |args|
          payload = args[:dependency_submission].payload
          expect(payload[:manifests]).to be_a(Hash)

          # We should have metadata indicating a successful snapshot
          expect(payload[:metadata][:status]).to eql(GithubApi::DependencySubmission::SnapshotStatus::DEGRADED.serialize)
          expect(payload[:metadata][:reason]).to eql(GithubApi::DependencySubmission::DEGRADED_REASON_SUBDEPENDENCY_ERR)
          expect(payload[:metadata][:scanned_manifest_path]).to eql("rubygems::/")
        end

        expect(service).to receive(:record_update_job_warning) do |args|
          expect(args[:warn_type]).to eq("dependency_graph_incomplete")
          expect(args[:warn_title]).to eq("dependency graph incomplete")
          expect(args[:warn_description]).to include("github.com/dependabot/cli")
        end

        update_graph_processor.run
      end
    end

    context "when the error is an unknown type" do
      before do
        original_grapher_class = Dependabot::DependencyGraphers.for_package_manager(job.package_manager)

        failing_grapher_class = Class.new(original_grapher_class) do
          def initialize(file_parser:)
            super
            @raise_once = true
          end

          def fetch_subdependencies(_dependency)
            if @raise_once
              @raise_once = false
              raise StandardError, "boom"
            end
            []
          end
        end

        allow(Dependabot::DependencyGraphers).to receive(:for_package_manager)
          .with(job.package_manager).and_return(failing_grapher_class)
      end

      it "records a warning and still submits a dependency submission" do
        expect(service).to receive(:create_dependency_submission) do |args|
          payload = args[:dependency_submission].payload
          expect(payload[:manifests]).to be_a(Hash)
        end

        expect(service).to receive(:record_update_job_warning) do |args|
          expect(args[:warn_type]).to eq("dependency_graph_incomplete")
          expect(args[:warn_title]).to eq("dependency graph incomplete")
          expect(args[:warn_description]).to include("Failed to fetch subdependencies")
        end

        update_graph_processor.run
      end
    end
  end

  context "when the dependency submission API is unavailable" do
    let(:directories) { [directory] }
    let(:directory) { "/" }
    let(:repo_contents_path) { build_tmp_repo("bundler/original", path: "") }

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: directory
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: directory
        )
      ]
    end

    before do
      allow(service).to receive(:create_dependency_submission)
        .and_raise(Dependabot::ApiError, "Service unavailable")
      allow(service).to receive(:capture_exception)
    end

    it "records a snapshots_unavailable_graph_error and does not retry submission" do
      expect(service).to receive(:record_update_job_error) do |args|
        expect(args[:error_type]).to eq("snapshots_unavailable_graph_error")
        expect(args[:error_details]).to include(
          message: "Unable to submit data to the Dependency Snapshot API"
        )
      end

      update_graph_processor.run
    end

    it "does not try to send an empty submission on this error" do
      expect(service).to receive(:create_dependency_submission).once.and_raise(Dependabot::ApiError)
      expect(service).to receive(:record_update_job_error)

      update_graph_processor.run
    end

    it "records a failed workflow result" do
      expect(service).to receive(:record_workflow_result).with(
        directory: "/",
        status: "failed",
        details: "Unable to submit data to the Dependency Snapshot API"
      )

      update_graph_processor.run
    end
  end

  context "when external code execution is rejected" do
    let(:directories) { [dir1, dir2] }
    let(:dir1) { "/" }
    let(:dir2) { "/subproject" }
    let(:repo_contents_path) { build_tmp_repo("bundler/original", path: "") }

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: dir1
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: dir1
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: dir2
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: dir2
        )
      ]
    end

    before do
      allow(Dependabot::FileParsers).to receive(:for_package_manager)
        .and_raise(Dependabot::UnexpectedExternalCode)
    end

    context "when executing standalone" do
      before do
        allow(Dependabot::Environment).to receive(:github_actions?).and_return(false)
      end

      it "records a warning for each directory" do
        expect(service).to receive(:record_update_job_warning).with(
          warn_type: "unexpected_external_code",
          warn_title: "Refusing to execute external code",
          warn_description: "Cannot process directory / without external code execution"
        )
        expect(service).to receive(:record_update_job_warning).with(
          warn_type: "unexpected_external_code",
          warn_title: "Refusing to execute external code",
          warn_description: "Cannot process directory /subproject without external code execution"
        )

        update_graph_processor.run
      end

      it "does not send any dependency submissions" do
        expect(service).not_to receive(:create_dependency_submission)

        update_graph_processor.run
      end

      it "does not halt processing of remaining directories" do
        call_count = 0
        allow(service).to receive(:record_update_job_warning) { call_count += 1 }

        update_graph_processor.run

        expect(call_count).to eq(2)
      end

      it "does not record workflow results when not in GitHub Actions" do
        expect(service).not_to receive(:record_workflow_result)

        update_graph_processor.run
      end
    end

    context "when executing in GitHub Actions" do
      before do
        allow(Dependabot::Environment).to receive(:github_actions?).and_return(true)
      end

      it "sends a FAILED empty submission for each directory" do
        expect(service).to receive(:create_dependency_submission).twice do |args|
          payload = args[:dependency_submission].payload
          expect(payload[:metadata][:status]).to eql(
            GithubApi::DependencySubmission::SnapshotStatus::FAILED.serialize
          )
          expect(payload[:metadata][:reason]).to eql("unexpected_external_code")
        end

        update_graph_processor.run
      end

      it "records a warning for each directory" do
        expect(service).to receive(:record_update_job_warning).twice

        update_graph_processor.run
      end

      it "records a failed workflow result for each directory" do
        expect(service).to receive(:record_workflow_result).with(
          directory: "/",
          status: "failed",
          details: a_string_including("Dependabot refused to execute external code")
        )
        expect(service).to receive(:record_workflow_result).with(
          directory: "/subproject",
          status: "failed",
          details: a_string_including("Dependabot refused to execute external code")
        )

        update_graph_processor.run
      end
    end
  end
end
