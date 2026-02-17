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

    let(:support_files_only_error_message) { described_class::SUPPORT_FILES_ONLY_ERROR_MESSAGE }
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

    def build_support_files(names)
      names.map do |name|
        Dependabot::DependencyFile.new(
          name: name,
          content: "content",
          directory: "/",
          support_file: true
        )
      end
    end

    def expect_support_files_only_error(
      dependency_info:, support_file_names:, omitted_support_file_count: 0, expected_message: nil
    )
      expect { create_change }.to raise_error(described_class::SupportFilesOnly) { |error|
        expect(error.dependency_info).to eq(dependency_info)
        expect(error.support_file_names).to eq(support_file_names)
        expect(error.omitted_support_file_count).to eq(omitted_support_file_count)
        if expected_message
          expect(error.message).to eq(expected_message)
        else
          expect(error.message).to include(support_files_only_error_message)
        end
      }
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
            Dependabot::DependabotError,
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
            Dependabot::DependabotError,
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
            Dependabot::DependabotError,
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

      it "warns with excluded support file names" do
        expect(Dependabot.logger)
          .to receive(:warn)
          .with(satisfy { |message|
            message.include?(support_files_only_error_message) &&
              message.include?("for: #{single_dependency_info}") &&
              message.include?("excluded support files:") &&
              message.include?("sub_dep") &&
              message.include?("sub_dep.lock") &&
              !message.include?("(and")
          })

        expect_support_files_only_error(
          dependency_info: single_dependency_info,
          support_file_names: %w(sub_dep sub_dep.lock)
        )
      end

      it "collects notices before raising" do
        expect_support_files_only_error(
          dependency_info: single_dependency_info,
          support_file_names: %w(sub_dep sub_dep.lock)
        )

        expect(notices).to eq(updater_notices)
      end

      it "exposes immutable support file names on the raised error" do
        expect { create_change }.to raise_error(described_class::SupportFilesOnly) { |error|
          expect(error.support_file_names).to be_frozen
          expect(error.support_file_names).to all(be_frozen)
          expect { error.support_file_names << "new_support_file" }.to raise_error(FrozenError)
        }
      end

      it "exposes immutable dependency info on the raised error" do
        expect { create_change }.to raise_error(described_class::SupportFilesOnly) { |error|
          expect(error.dependency_info).to be_frozen
        }
      end

      it "defensively copies support file names and dependency info" do
        dependency_info = +"dummy-pkg-b (1.1.0 → 1.2.0)"
        support_file_names = ["sub_dep", "sub_dep.lock"]

        error = described_class::SupportFilesOnly.new(
          dependency_info: dependency_info,
          support_file_names: support_file_names,
          omitted_support_file_count: 0
        )

        dependency_info << " (mutated)"
        support_file_names << "new_support_file"

        expect(error.dependency_info).to eq("dummy-pkg-b (1.1.0 → 1.2.0)")
        expect(error.support_file_names).to eq(%w(sub_dep sub_dep.lock))
        expect(error.message).to start_with(
          "#{support_files_only_error_message} for: dummy-pkg-b (1.1.0 → 1.2.0);"
        )
        expect(error.message).to include("excluded support files: sub_dep, sub_dep.lock")
        expect(error.message).not_to include("new_support_file")
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

      it "raises an exception with sorted and unique dependency names" do
        expected_message =
          "FileUpdater returned only support files for: dummy-pkg-a, dummy-pkg-b; " \
          "excluded support files: sub_dep, sub_dep.lock"

        expect_support_files_only_error(
          dependency_info: "dummy-pkg-a, dummy-pkg-b",
          support_file_names: %w(sub_dep sub_dep.lock),
          expected_message: expected_message
        )
      end
    end

    context "when support file names exceed warning limit" do
      let(:change_source) { lead_dependency_change_source }
      let(:support_files) do
        file_names = Array.new(described_class::SUPPORT_FILE_WARNING_NAME_LIMIT + 1) do |index|
          "support_#{index}.txt"
        end
        build_support_files(file_names)
      end

      before do
        stub_file_updater(updated_dependency_files: support_files)
      end

      it "warns with the listed limit and omitted count" do
        expect(Dependabot.logger)
          .to receive(:warn)
          .with(satisfy { |message|
            message.include?(support_files_only_error_message) &&
              message.include?("excluded support files:") &&
              message.include?("(and 1 more)")
          })

        expect_support_files_only_error(
          dependency_info: single_dependency_info,
          support_file_names: Array.new(described_class::SUPPORT_FILE_WARNING_NAME_LIMIT) do |index|
            "support_#{index}.txt"
          end,
          omitted_support_file_count: 1
        )
      end
    end

    context "when support file names include multi-digit suffixes" do
      let(:change_source) { lead_dependency_change_source }
      let(:support_files) do
        build_support_files([10, 2, 1].map { |index| "support_#{index}.txt" })
      end

      before do
        stub_file_updater(updated_dependency_files: support_files)
      end

      it "orders support file names naturally in the raised error" do
        expect_support_files_only_error(
          dependency_info: single_dependency_info,
          support_file_names: %w(support_1.txt support_2.txt support_10.txt)
        )
      end
    end

    context "when support file names differ in casing" do
      let(:change_source) { lead_dependency_change_source }
      let(:support_files) do
        build_support_files(["Support_2.txt", "support_10.txt", "support_1.txt"])
      end

      before do
        stub_file_updater(updated_dependency_files: support_files)
      end

      it "orders support file names naturally regardless of case" do
        expect_support_files_only_error(
          dependency_info: single_dependency_info,
          support_file_names: ["support_1.txt", "Support_2.txt", "support_10.txt"]
        )
      end
    end
  end
end
