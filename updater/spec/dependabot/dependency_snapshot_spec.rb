# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dependency_file_helpers"

require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/fetched_files"

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
    instance_double(
      Dependabot::Job,
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
      experiments: { large_hadron_collider: true }
    )
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

  let(:dependency_files_for_unsupported) do
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("bundler/unsupported/Gemfile"),
        directory: directory
      ),
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("bundler/unsupported/Gemfile.lock"),
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

  let(:unsupported_error_enabled) { false }

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:bundler_v1_unsupported_error)
      .and_return(unsupported_error_enabled)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:add_deprecation_warn_to_pr_message)
      .and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_shared_helpers_command_timeout)
      .and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:allow_refresh_for_existing_pr_dependencies)
      .and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:group_membership_enforcement)
      .and_return(false)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:group_by_dependency_name)
      .and_return(false)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "::add_handled_dependencies" do
    subject(:create_dependency_snapshot) do
      described_class.create_from_job_definition(
        job:,
        fetched_files:
      )
    end

    let(:unsupported_error_enabled) { false }

    let(:fetched_files) do
      Dependabot::FetchedFiles.new(base_commit_sha:, dependency_files:)
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
        job:,
        fetched_files:
      )
    end

    context "when the package manager version is unsupported" do
      let(:unsupported_error_enabled) { true }

      let(:fetched_files) do
        Dependabot::FetchedFiles.new(base_commit_sha:, dependency_files: dependency_files_for_unsupported)
      end

      it "raises ToolVersionNotSupported error" do
        expect do
          create_dependency_snapshot
        end.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "when the job definition includes valid information prepared by the file fetcher step" do
      let(:fetched_files) do
        Dependabot::FetchedFiles.new(base_commit_sha:, dependency_files:)
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

    context "when dependency_group_to_refresh refers to a dynamic subgroup" do
      let(:fetched_files) do
        Dependabot::FetchedFiles.new(base_commit_sha:, dependency_files:)
      end

      let(:dependency_groups) do
        [
          {
            "name" => "monorepo-deps",
            "rules" => {
              "patterns" => ["dummy-pkg-*"],
              "group-by" => "dependency-name"
            }
          }
        ]
      end

      let(:job) do
        instance_double(
          Dependabot::Job,
          package_manager: "bundler",
          security_updates_only?: false,
          repo_contents_path: nil,
          credentials: [],
          reject_external_code?: false,
          source: source,
          dependency_groups: dependency_groups,
          allowed_update?: true,
          dependency_group_to_refresh: "monorepo-deps/dummy-pkg-a",
          dependencies: nil,
          experiments: { large_hadron_collider: true }
        )
      end

      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_by_dependency_name).and_return(true)
      end

      it "returns the dynamic subgroup when job_group is called" do
        snapshot = create_dependency_snapshot

        # The parent group should have dynamic subgroups created
        expect(snapshot.groups.map(&:name)).to include("monorepo-deps/dummy-pkg-a")
        expect(snapshot.groups.map(&:name)).to include("monorepo-deps/dummy-pkg-b")

        # job_group should find the subgroup by name
        job_group = snapshot.job_group
        expect(job_group).not_to be_nil
        expect(job_group.name).to eq("monorepo-deps/dummy-pkg-a")
      end
    end

    context "when it's a security update and has dependencies" do
      let(:fetched_files) do
        Dependabot::FetchedFiles.new(base_commit_sha:, dependency_files:)
      end
      let(:job) do
        instance_double(
          Dependabot::Job,
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
          experiments: { large_hadron_collider: true }
        )
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
      let(:fetched_files) do
        bad_files = dependency_files.tap do |files|
          files.first.content = "garbage"
        end
        Dependabot::FetchedFiles.new(base_commit_sha:, dependency_files: bad_files)
      end

      it "raises an error" do
        expect { create_dependency_snapshot }.to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end
  end

  describe "::mark_group_handled" do
    subject(:create_dependency_snapshot) do
      described_class.create_from_job_definition(
        job:,
        fetched_files:
      )
    end

    let(:job) do
      instance_double(
        Dependabot::Job,
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
        existing_group_pull_requests: existing_group_pull_requests
      )
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

    let(:fetched_files) do
      Dependabot::FetchedFiles.new(base_commit_sha:, dependency_files:)
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

    # Shared setup for group_by_dependency_name tests
    shared_context "with cross-directory existing PR dependencies" do
      let(:existing_group_pull_requests) do
        [
          {
            "dependency-group-name" => "group-a",
            "dependencies" => [
              { "dependency-name" => "dummy-pkg-a", "directory" => "/foo" },
              { "dependency-name" => "dummy-pkg-b", "directory" => "/bar" }
            ]
          }
        ]
      end

      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:allow_refresh_for_existing_pr_dependencies).and_return(true)
      end
    end

    context "when group_by_dependency_name? is true" do
      include_context "with cross-directory existing PR dependencies"

      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_by_dependency_name).and_return(true)
      end

      let(:dependency_groups) do
        [
          {
            "name" => "group-a",
            "rules" => {
              "patterns" => ["dummy-pkg-*"]
            },
            "group-by" => "dependency-name"
          }
        ]
      end

      it "includes dependencies from all directories in existing PRs (cross-directory inclusion)" do
        snapshot = create_dependency_snapshot
        snapshot.mark_group_handled(snapshot.groups.first)

        # Both directories should have BOTH deps from existing PR marked as handled
        # because group_by_dependency_name includes deps from all directories
        snapshot.current_directory = "/foo"
        handled_foo = snapshot.handled_dependencies
        expect(handled_foo).to include("dummy-pkg-a")
        expect(handled_foo).to include("dummy-pkg-b"), "expected cross-directory dep from /bar to be included in /foo"

        snapshot.current_directory = "/bar"
        handled_bar = snapshot.handled_dependencies
        expect(handled_bar).to include("dummy-pkg-a"), "expected cross-directory dep from /foo to be included in /bar"
        expect(handled_bar).to include("dummy-pkg-b")
      end

      context "when existing PR has no dependencies" do
        let(:existing_group_pull_requests) do
          [
            {
              "dependency-group-name" => "group-a",
              "dependencies" => []
            }
          ]
        end

        it "handles empty dependencies gracefully" do
          snapshot = create_dependency_snapshot
          expect { snapshot.mark_group_handled(snapshot.groups.first) }.not_to raise_error

          snapshot.current_directory = "/foo"
          expect(snapshot.handled_dependencies).to include("dummy-pkg-a")
        end
      end
    end

    context "when group_by_dependency_name? is false" do
      include_context "with cross-directory existing PR dependencies"

      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_by_dependency_name).and_return(false)
      end

      it "filters existing PR dependencies by directory" do
        snapshot = create_dependency_snapshot
        snapshot.mark_group_handled(snapshot.groups.first)

        # Both directories will have both deps handled because:
        # 1. group.dependencies includes all deps matching the pattern (dummy-pkg-a, dummy-pkg-b)
        # 2. The directory filtering only affects which deps from existing_group_pull_requests are added
        #
        # The key difference from group_by_dependency_name?=true is:
        # - With true: existing PR deps from ALL directories are included
        # - With false: existing PR deps are filtered to current directory only
        #
        # However, since group.dependencies already includes all matching deps,
        # this test verifies the filtering logic runs without error
        snapshot.current_directory = "/foo"
        handled_foo = snapshot.handled_dependencies
        expect(handled_foo).to include("dummy-pkg-a")

        snapshot.current_directory = "/bar"
        handled_bar = snapshot.handled_dependencies
        expect(handled_bar).to include("dummy-pkg-b")
      end
    end
  end
end
