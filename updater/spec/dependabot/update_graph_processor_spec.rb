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
      dependency_files:
    )
  end

  let(:service) do
    instance_double(
      Dependabot::Service,
      create_dependency_submission: nil
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

  let(:branch) { "develop" }

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "dependabot-fixtures/dependabot-test-ruby-package",
      directories: directories,
      branch: branch
    )
  end

  let(:job) do
    instance_double(
      Dependabot::Job,
      id: "42",
      package_manager: "bundler",
      repo_contents_path: nil,
      credentials: credentials,
      source: source,
      reject_external_code?: false,
      experiments: { large_hadron_collider: true }
    )
  end

  let(:base_commit_sha) { "fake-sha" }

  context "with a basic Gemfile project" do
    let(:directories) { [directory] }
    let(:directory) { "/" }

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
        expect(payload[:job][:correlator]).to eq("dependabot-bundler-Gemfile.lock")
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

        dependency1 = lockfile[:resolved]["dummy-pkg-a"]
        expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a@2.0.0")

        dependency2 = lockfile[:resolved]["dummy-pkg-b"]
        expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b@1.1.0")
      end

      update_graph_processor.run
    end
  end

  context "with a small sinatra app" do
    let(:directories) { [directory] }
    let(:directory) { "/" }

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
        %w(sinatra pry rspec capybara).each do |pkg_name|
          resolved_dep = lockfile[:resolved][pkg_name]

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
        rack = lockfile[:resolved]["rack"]
        expect(rack[:package_url]).to eql("pkg:gem/rack@3.1.16")
        expect(rack[:relationship]).to eq("indirect")
        expect(rack[:scope]).to eq("runtime")

        addressable = lockfile[:resolved]["addressable"]
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
      expect(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload

        next unless payload[:job][:correlator] == "dependabot-bundler-Gemfile.lock"

        # Check we have a Sinatra app with 28 dependencies
        expect(payload[:manifests].length).to eq(1)
        lockfile = payload[:manifests].fetch("/Gemfile.lock")

        expect(lockfile[:resolved].length).to eq(28)

        expect(lockfile[:resolved].values.count { |dep| dep[:relationship] == "direct" }).to eq(4)
        expect(lockfile[:resolved].values.count { |dep| dep[:relationship] == "indirect" }).to eq(24)
      end

      update_graph_processor.run
    end

    it "correctly snapshots the second directory" do
      expect(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload

        next unless payload[:job][:correlator] == "dependabot-bundler-subproj-Gemfile.lock"

        # Check we have the simple app with 2 dependencies
        expect(payload[:manifests].length).to eq(1)
        lockfile = payload[:manifests].fetch("/Gemfile.lock")

        expect(lockfile[:resolved].length).to eq(2)

        dependency1 = lockfile[:resolved]["dummy-pkg-a"]
        expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a@2.0.0")
        dependency2 = lockfile[:resolved]["dummy-pkg-b"]
        expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b@1.1.0")
      end

      update_graph_processor.run
    end
  end

  context "with vendored files" do
    let(:directories) { [directory] }
    let(:directory) { "/" }

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

        dependency1 = gemfile[:resolved]["dummy-pkg-a"]
        expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a")

        dependency2 = gemfile[:resolved]["dummy-pkg-b"]
        expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b")
      end

      update_graph_processor.run
    end
  end

  # This is mainly for documentation purposes, this is unlikely to happen in the real world.
  context "with a set of empty dependency files" do
    let(:directories) { [directory] }
    let(:directory) { "/" }

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

    it "generates a snapshot with metadata and an empty manifest list" do
      expect(service).to receive(:create_dependency_submission) do |args|
        payload = args[:dependency_submission].payload

        expect(payload[:job][:correlator]).to eq("dependabot-bundler-Gemfile.lock")
        expect(payload[:manifests]).to be_empty
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

      # FIXME(brrygrdn): We should obtain the ref from git -or- inject it via the backend service
      it "assumes refs/heads/main instead of using the real default branch" do
        expect(service).to receive(:create_dependency_submission) do |args|
          payload = args[:dependency_submission].payload

          expect(payload[:ref]).to eql("refs/heads/main")
        end

        update_graph_processor.run
      end
    end
  end
end
