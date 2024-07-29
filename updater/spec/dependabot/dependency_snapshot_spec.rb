# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dependency_file_helpers"

require "dependabot/dependency_file"
require "dependabot/errors"

require "dependabot/dependency_snapshot"
require "dependabot/job"

require "dependabot/bundler"

RSpec.describe Dependabot::DependencySnapshot do
  include DependencyFileHelpers

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "dependabot-fixtures/dependabot-test-ruby-package",
      directory: "/",
      branch: nil,
      api_endpoint: "https://api.github.com/",
      hostname: "github.com"
    )
  end

  let(:directory) { "/" }
  let(:directories) { nil }

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "dependabot-fixtures/dependabot-test-ruby-package",
      directory: directory,
      directories: directories
    )
  end

  let(:job) do
    instance_double(Dependabot::Job,
                    package_manager: "bundler",
                    security_updates_only?: false,
                    repo_contents_path: nil,
                    credentials: [],
                    reject_external_code?: false,
                    source: source,
                    dependency_groups: dependency_groups,
                    allowed_update?: true,
                    dependency_group_to_refresh: nil,
                    dependencies: nil,
                    experiments: { large_hadron_collider: true })
  end

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

  let(:dependency_groups) do
    [
      {
        "name" => "group-a",
        "rules" => {
          "patterns" => ["dummy-pkg-*"],
          "exclude-patterns" => ["dummy-pkg-b"]
        }
      }
    ]
  end

  let(:base_commit_sha) do
    "mock-sha"
  end

  describe "::add_handled_dependencies" do
    subject(:create_dependency_snapshot) do
      described_class.create_from_job_definition(
        job: job,
        job_definition: job_definition
      )
    end

    let(:job_definition) do
      {
        "base_commit_sha" => base_commit_sha,
        "base64_dependency_files" => encode_dependency_files(dependency_files)
      }
    end

    it "handles dependencies" do
      snapshot = create_dependency_snapshot
      snapshot.add_handled_dependencies(%w(a b))
      expect(snapshot.handled_dependencies).to eq(Set.new(%w(a b)))
    end

    context "when there are multiple directories" do
      let(:directory) { nil }
      let(:directories) { %w(/foo /bar) }
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "Gemfile",
            content: fixture("bundler/original/Gemfile"),
            directory: "/foo"
          ),
          Dependabot::DependencyFile.new(
            name: "Gemfile",
            content: fixture("bundler/original/Gemfile"),
            directory: "/bar"
          )
        ]
      end

      it "handles dependencies per directory" do
        snapshot = create_dependency_snapshot
        snapshot.current_directory = "/foo"
        snapshot.add_handled_dependencies(%w(a b))
        expect(snapshot.handled_dependencies).to eq(Set.new(%w(a b)))

        snapshot.current_directory = "/bar"
        expect(snapshot.handled_dependencies).to eq(Set.new)
        snapshot.add_handled_dependencies(%w(c d))
        expect(snapshot.handled_dependencies).to eq(Set.new(%w(c d)))

        snapshot.current_directory = "/foo"
        expect(snapshot.handled_dependencies).to eq(Set.new(%w(a b)))
      end
    end
  end

  describe "::create_from_job_definition" do
    subject(:create_dependency_snapshot) do
      described_class.create_from_job_definition(
        job: job,
        job_definition: job_definition
      )
    end

    context "when the job definition includes valid information prepared by the file fetcher step" do
      let(:job_definition) do
        {
          "base_commit_sha" => base_commit_sha,
          "base64_dependency_files" => encode_dependency_files(dependency_files)
        }
      end

      it "creates a new instance which has parsed the dependencies from the provided files" do
        snapshot = create_dependency_snapshot

        expect(snapshot).to be_a(described_class)
        expect(snapshot.base_commit_sha).to eql("mock-sha")
        expect(snapshot.dependency_files).to all(be_a(Dependabot::DependencyFile))
        expect(snapshot.dependency_files.map(&:content)).to eql(dependency_files.map(&:content))
        expect(snapshot.dependencies.count).to be(2)
        expect(snapshot.dependencies).to all(be_a(Dependabot::Dependency))
        expect(snapshot.dependencies.map(&:name)).to eql(%w(dummy-pkg-a dummy-pkg-b))
      end

      it "passes any job experiments on to the FileParser it instantiates as options" do
        expect(Dependabot::Bundler::FileParser).to receive(:new).with(
          dependency_files: anything,
          repo_contents_path: nil,
          source: source,
          credentials: [],
          reject_external_code: false,
          options: { large_hadron_collider: true }
        ).and_call_original

        create_dependency_snapshot
      end

      it "correctly instantiates any configured dependency groups" do
        snapshot = create_dependency_snapshot

        expect(snapshot.groups.length).to be(1)

        group = snapshot.groups.last

        expect(group.name).to eql("group-a")
        expect(group.dependencies.length).to be(1)
        expect(group.dependencies.first.name).to eql("dummy-pkg-a")

        expect(snapshot.ungrouped_dependencies.length).to be(2)

        snapshot.current_directory = directory
        snapshot.add_handled_dependencies("dummy-pkg-a")
        expect(snapshot.ungrouped_dependencies.first.name).to eql("dummy-pkg-b")

        Dependabot::Experiments.reset!
      end
    end

    context "when it's a security update and has dependencies" do
      let(:job_definition) do
        {
          "base_commit_sha" => base_commit_sha,
          "base64_dependency_files" => encode_dependency_files(dependency_files),
          "security_updates_only" => true
        }
      end
      let(:job) do
        instance_double(Dependabot::Job,
                        package_manager: "bundler",
                        security_updates_only?: true,
                        repo_contents_path: nil,
                        credentials: [],
                        reject_external_code?: false,
                        source: source,
                        dependency_groups: dependency_groups,
                        dependencies: ["dummy-pkg-a"],
                        allowed_update?: false,
                        dependency_group_to_refresh: nil,
                        experiments: { large_hadron_collider: true })
      end

      it "uses the dependencies even if they aren't allowed" do
        snapshot = create_dependency_snapshot

        expect(snapshot).to be_a(described_class)
        expect(snapshot.base_commit_sha).to eql("mock-sha")
        expect(snapshot.dependency_files).to all(be_a(Dependabot::DependencyFile))
        expect(snapshot.dependency_files.map(&:content)).to eql(dependency_files.map(&:content))
        expect(snapshot.dependencies.count).to be(2)
        expect(snapshot.dependencies).to all(be_a(Dependabot::Dependency))
        expect(snapshot.allowed_dependencies.map(&:name)).to eql(%w(dummy-pkg-a))
      end
    end

    context "when there is a parser error" do
      let(:job_definition) do
        {
          "base_commit_sha" => base_commit_sha,
          "base64_dependency_files" => encode_dependency_files(dependency_files).tap do |files|
            files.first["content"] = Base64.encode64("garbage")
          end
        }
      end

      it "raises an error" do
        expect { create_dependency_snapshot }.to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "when the job definition does not have the 'base64_dependency_files' key" do
      let(:job_definition) do
        {
          "base_commit_sha" => base_commit_sha
        }
      end

      it "raises an error" do
        expect { create_dependency_snapshot }.to raise_error(KeyError)
      end
    end

    context "when the job definition does not have the 'base_commit_sha' key" do
      let(:job_definition) do
        {
          "base64_dependency_files" => encode_dependency_files(dependency_files)
        }
      end

      it "raises an error" do
        expect { create_dependency_snapshot }.to raise_error(KeyError)
      end
    end
  end

  describe "::mark_group_handled" do
    subject(:create_dependency_snapshot) do
      described_class.create_from_job_definition(
        job: job,
        job_definition: job_definition
      )
    end

    let(:job) do
      instance_double(Dependabot::Job,
                      package_manager: "bundler",
                      security_updates_only?: false,
                      repo_contents_path: nil,
                      credentials: [],
                      reject_external_code?: false,
                      source: source,
                      dependency_groups: dependency_groups,
                      allowed_update?: true,
                      dependency_group_to_refresh: nil,
                      dependencies: nil,
                      experiments: { large_hadron_collider: true },
                      existing_group_pull_requests: existing_group_pull_requests)
    end

    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "dependabot-fixtures/dependabot-test-ruby-package",
        directories: %w(/foo /bar),
        branch: nil,
        api_endpoint: "https://api.github.com/",
        hostname: "github.com"
      )
    end

    let(:dependency_groups) do
      [
        {
          "name" => "group-a",
          "rules" => {
            "patterns" => ["dummy-pkg-*"],
            "exclude-patterns" => ["dummy-pkg-b"]
          }
        }
      ]
    end

    let(:existing_group_pull_requests) do
      [
        {
          "group" => "group-a",
          "dependencies" => %w(dummy-pkg-a)
        }
      ]
    end

    let(:job_definition) do
      {
        "base_commit_sha" => base_commit_sha,
        "base64_dependency_files" => encode_dependency_files(dependency_files)
      }
    end

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: "/foo"
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: "/foo"
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: "/bar"
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: "/bar"
        )
      ]
    end

    it "marks the dependencies handled for all directories" do
      snapshot = create_dependency_snapshot
      snapshot.mark_group_handled(snapshot.groups.first)

      snapshot.current_directory = "/foo"
      expect(snapshot.handled_dependencies).to eq(Set.new(%w(dummy-pkg-a)))

      snapshot.current_directory = "/bar"
      expect(snapshot.handled_dependencies).to eq(Set.new(%w(dummy-pkg-a)))
    end

    context "when there are no existing group pull requests" do
      let(:existing_group_pull_requests) { [] }

      it "marks the dependencies that would have been covered as handled" do
        snapshot = create_dependency_snapshot
        snapshot.mark_group_handled(snapshot.groups.first)

        snapshot.current_directory = "/foo"
        expect(snapshot.handled_dependencies).to eq(Set.new(%w(dummy-pkg-a)))

        snapshot.current_directory = "/bar"
        expect(snapshot.handled_dependencies).to eq(Set.new(%w(dummy-pkg-a)))
      end
    end
  end
end
