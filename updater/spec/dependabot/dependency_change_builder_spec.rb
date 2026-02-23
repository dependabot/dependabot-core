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

  let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: "/.") }

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
    [build_dependency(name: "dummy-pkg-b", version: "1.2.0", previous_version: "1.1.0")]
  end

  describe "::create_from" do
    subject(:create_change) do
      described_class.create_from(
        job: job,
        dependency_files: dependency_files,
        updated_dependencies: updated_dependencies,
        change_source: change_source,
        notices: notices
      )
    end

    let(:notices) { [] }
    let(:lead_dependency_change_source) { build_dependency(name: "dummy-pkg-b", version: "1.1.0") }
    let(:single_dependency_info) { "dummy-pkg-b (1.1.0 → 1.2.0)" }
    let(:file_updater_class) { class_double(Dependabot::Bundler::FileUpdater) }

    def stub_file_updater(updated_dependency_files:, notices: [])
      file_updater = instance_double(
        Dependabot::Bundler::FileUpdater,
        updated_dependency_files: updated_dependency_files,
        notices: notices
      )

      allow(Dependabot::FileUpdaters).to receive(:for_package_manager)
        .with("bundler")
        .and_return(file_updater_class)
      allow(file_updater_class).to receive(:new).and_return(file_updater)
    end

    def build_dependency(name:, version:, previous_version: nil)
      requirement = {
        file: "Gemfile",
        requirement: "~> #{version}",
        groups: [],
        source: nil
      }

      dependency_args = {
        name: name,
        package_manager: "bundler",
        version: version,
        requirements: [requirement]
      }

      if previous_version
        previous_requirement = {
          file: "Gemfile",
          requirement: "~> #{previous_version}",
          groups: [],
          source: nil
        }

        dependency_args[:previous_version] = previous_version
        dependency_args[:previous_requirements] = [previous_requirement]
      end

      Dependabot::Dependency.new(**dependency_args)
    end

    def dependency_group_source
      Dependabot::DependencyGroup.new(name: "dummy-pkg-*", rules: { patterns: ["dummy-pkg-*"] })
    end

    context "when the source is a lead dependency" do
      let(:change_source) { lead_dependency_change_source }

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
        stub_file_updater(updated_dependency_files: dependency_files)

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
      let(:change_source) { dependency_group_source }

      it "creates a new DependencyChange flagged as a grouped update" do
        dependency_change = create_change

        expect(dependency_change).to be_a(Dependabot::DependencyChange)
        expect(dependency_change).to be_grouped_update
      end
    end

    context "when there are no file changes" do
      let(:change_source) { lead_dependency_change_source }

      before do
        stub_file_updater(updated_dependency_files: [])
      end

      it "raises an exception with diagnostic dependency details" do
        expect { create_change }
          .to raise_error(
            Dependabot::DependencyFileContentNotChanged,
            "FileUpdater failed to update any files for: dummy-pkg-b (1.1.0 → 1.2.0)"
          )
      end
    end

    context "when multiple dependencies have no file changes" do
      let(:updated_dependencies) do
        [
          build_dependency(name: "dummy-pkg-b", version: "1.2.0", previous_version: "1.1.0"),
          build_dependency(name: "dummy-pkg-a", version: "2.0.0", previous_version: "1.9.0")
        ]
      end

      let(:change_source) { dependency_group_source }

      before do
        stub_file_updater(updated_dependency_files: [])
      end

      it "raises an exception listing dependency names" do
        expect { create_change }
          .to raise_error(
            Dependabot::DependencyFileContentNotChanged,
            "FileUpdater failed to update any files for: dummy-pkg-a, dummy-pkg-b"
          )
      end
    end

    context "when duplicate dependency names have no file changes" do
      let(:updated_dependencies) do
        [
          build_dependency(name: "dummy-pkg-b", version: "1.2.0", previous_version: "1.1.0"),
          build_dependency(name: "dummy-pkg-b", version: "1.3.0", previous_version: "1.2.0")
        ]
      end

      let(:change_source) { dependency_group_source }

      before do
        stub_file_updater(updated_dependency_files: [])
      end

      it "raises an exception with unique dependency names" do
        expect { create_change }
          .to raise_error(
            Dependabot::DependencyFileContentNotChanged,
            "FileUpdater failed to update any files for: dummy-pkg-b"
          )
      end
    end

    context "when only support files are returned" do
      let(:change_source) { lead_dependency_change_source }
      let(:support_files) { dependency_files.select(&:support_file?) }
      let(:updated_support_files) { [support_files.last, support_files.first, support_files.last] }
      let(:updater_notices) { [instance_double(Dependabot::Notice)] }

      before do
        stub_file_updater(updated_dependency_files: updated_support_files, notices: updater_notices)
      end

      it "raises a generic no-files error" do
        expect { create_change }
          .to raise_error(
            Dependabot::DependencyFileContentNotChanged,
            "FileUpdater failed to update any files for: dummy-pkg-b (1.1.0 → 1.2.0)"
          )
      end

      it "collects notices before raising" do
        expect { create_change }
          .to raise_error(
            Dependabot::DependencyFileContentNotChanged,
            "FileUpdater failed to update any files for: dummy-pkg-b (1.1.0 → 1.2.0)"
          )

        expect(notices).to eq(updater_notices)
      end
    end

    context "when grouped updates return only support files" do
      let(:updated_dependencies) do
        [
          build_dependency(name: "dummy-pkg-b", version: "1.2.0", previous_version: "1.1.0"),
          build_dependency(name: "dummy-pkg-a", version: "2.0.0", previous_version: "1.9.0"),
          build_dependency(name: "dummy-pkg-b", version: "1.3.0", previous_version: "1.2.0")
        ]
      end
      let(:change_source) { dependency_group_source }
      let(:support_files) { dependency_files.select(&:support_file?) }

      before do
        stub_file_updater(updated_dependency_files: support_files)
      end

      it "raises a no-files error listing sorted and unique dependency names" do
        expect { create_change }
          .to raise_error(
            Dependabot::DependencyFileContentNotChanged,
            "FileUpdater failed to update any files for: dummy-pkg-a, dummy-pkg-b"
          )
      end
    end
  end
end
