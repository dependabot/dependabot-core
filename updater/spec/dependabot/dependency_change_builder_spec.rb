# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_change_builder"
require "dependabot/dependency_file"
require "dependabot/job"

require "dependabot/bundler"

RSpec.describe Dependabot::DependencyChangeBuilder do
  let(:job) do
    instance_double(
      Dependabot::Job,
      package_manager: "bundler",
      repo_contents_path: nil,
      credentials: [
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "github-token"
        }
      ],
      experiments: {},
      source: source
    )
  end

  let(:source_directory) { "/." }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: source_directory) }

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("bundler/original/Gemfile"),
        directory: "/",
        support_file: false
      ),
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("bundler/original/Gemfile.lock"),
        directory: "/",
        support_file: false
      ),
      Dependabot::DependencyFile.new(
        name: "sub_dep",
        content: fixture("bundler/original/sub_dep"),
        directory: "/",
        support_file: true
      ),
      Dependabot::DependencyFile.new(
        name: "sub_dep.lock",
        content: fixture("bundler/original/sub_dep.lock"),
        directory: "/",
        support_file: true
      )
    ]
  end

  let(:updated_dependencies) do
    [
      Dependabot::Dependency.new(
        name: "dummy-pkg-b",
        package_manager: "bundler",
        version: "1.2.0",
        previous_version: "1.1.0",
        requirements: [
          {
            file: "Gemfile",
            requirement: "~> 1.2.0",
            groups: [],
            source: nil
          }
        ],
        previous_requirements: [
          {
            file: "Gemfile",
            requirement: "~> 1.1.0",
            groups: [],
            source: nil
          }
        ]
      )
    ]
  end

  describe "::create_from" do
    subject(:create_change) do
      described_class.create_from(
        job: job,
        dependency_files: dependency_files,
        updated_dependencies: updated_dependencies,
        change_source: change_source
      )
    end

    context "when the source is a lead dependency" do
      let(:change_source) do
        Dependabot::Dependency.new(
          name: "dummy-pkg-b",
          package_manager: "bundler",
          version: "1.1.0",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.1.0",
              groups: [],
              source: nil
            }
          ]
        )
      end

      it "creates a new DependencyChange with the updated files" do
        dependency_change = create_change

        expect(dependency_change).to be_a(Dependabot::DependencyChange)
        expect(dependency_change.updated_dependencies).to eql(updated_dependencies)
        expect(dependency_change.updated_dependency_files.map(&:name)).to eql(["Gemfile", "Gemfile.lock"])
        expect(dependency_change).not_to be_grouped_update

        gemfile = dependency_change.updated_dependency_files.find { |file| file.name == "Gemfile" }
        expect(gemfile.content).to eql(fixture("bundler/updated/Gemfile"))

        lockfile = dependency_change.updated_dependency_files.find { |file| file.name == "Gemfile.lock" }
        expect(lockfile.content).to eql(fixture("bundler/updated/Gemfile.lock"))
      end

      it "does not include support files in the updated files" do
        allow_any_instance_of(Dependabot::Bundler::FileUpdater)
          .to receive(:updated_dependency_files)
          .and_return(dependency_files)

        dependency_change = described_class.create_from(
          job: job,
          dependency_files: dependency_files,
          updated_dependencies: updated_dependencies,
          change_source: change_source
        )

        updated_file_names = dependency_change.updated_dependency_files.map(&:name)
        expect(updated_file_names).not_to include("sub_dep", "sub_dep.lock")
      end
    end

    context "when the source is a dependency group" do
      let(:change_source) do
        Dependabot::DependencyGroup.new(name: "dummy-pkg-*", rules: { patterns: ["dummy-pkg-*"] })
      end

      it "creates a new DependencyChange flagged as a grouped update" do
        dependency_change = create_change

        expect(dependency_change).to be_a(Dependabot::DependencyChange)
        expect(dependency_change).to be_grouped_update
      end
    end

    context "when there are no file changes" do
      let(:change_source) do
        Dependabot::Dependency.new(
          name: "dummy-pkg-b",
          package_manager: "bundler",
          version: "1.1.0",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.1.0",
              groups: [],
              source: nil
            }
          ]
        )
      end

      before do
        allow_any_instance_of(Dependabot::Bundler::FileUpdater).to receive(:updated_dependency_files).and_return([])
      end

      it "raises an exception" do
        expect { create_change }.to raise_error(Dependabot::DependabotError)
      end
    end

    context "when dependencies share a lockfile across directories" do
      let(:source_directory) { "/WorkspacePackage1.jl/SubPackageA" }
      let(:manifest_path) { "/WorkspacePackage1.jl/Manifest.toml" }
      let(:lockfile_files) do
        [
          Dependabot::DependencyFile.new(
            name: "Project.toml",
            content: 'name = "SubPackageA"',
            directory: "/WorkspacePackage1.jl/SubPackageA",
            associated_lockfile_path: manifest_path
          ),
          Dependabot::DependencyFile.new(
            name: "Project.toml",
            content: 'name = "SubPackageB"',
            directory: "/WorkspacePackage1.jl/SubPackageB",
            associated_lockfile_path: manifest_path
          ),
          Dependabot::DependencyFile.new(
            name: "Manifest.toml",
            content: "manifest",
            directory: "/WorkspacePackage1.jl",
            associated_manifest_paths: [
              "/WorkspacePackage1.jl/SubPackageA/Project.toml",
              "/WorkspacePackage1.jl/SubPackageB/Project.toml"
            ]
          )
        ]
      end
      let(:dependency_files) { lockfile_files }
      let(:change_source) do
        Dependabot::Dependency.new(
          name: "JSON",
          package_manager: "julia",
          requirements: [{
            file: "WorkspacePackage1.jl/SubPackageA/Project.toml",
            requirement: "0.21",
            groups: [],
            source: nil
          }]
        )
      end
      let(:updated_dependencies) { [change_source] }

      it "keeps sibling project files needed for workspace manifest updates" do
        builder = described_class.new(
          job: job,
          dependency_files: dependency_files,
          updated_dependencies: updated_dependencies,
          change_source: change_source
        )

        files = builder.send(:dependency_files)
        sibling_path = "/WorkspacePackage1.jl/SubPackageB/Project.toml"
        expect(files.map(&:path)).to include(sibling_path)
      end
    end
  end
end
