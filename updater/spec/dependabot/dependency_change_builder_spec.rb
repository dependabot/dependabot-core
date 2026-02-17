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
    let(:support_files_only_error_message) { described_class::SUPPORT_FILES_ONLY_ERROR_MESSAGE }

    let(:lead_dependency_change_source) do
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

    subject(:create_change) do
      described_class.create_from(
        job: job,
        dependency_files: dependency_files,
        updated_dependencies: updated_dependencies,
        change_source: change_source
      )
    end

    def stub_file_updater(updated_dependency_files:)
      file_updater = instance_double(
        Dependabot::Bundler::FileUpdater,
        updated_dependency_files: updated_dependency_files,
        notices: []
      )

      expect(Dependabot::Bundler::FileUpdater)
        .to receive(:new)
        .with(hash_including(
                dependencies: updated_dependencies,
                dependency_files: dependency_files,
                repo_contents_path: nil
              ))
        .and_return(file_updater)
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
      let(:change_source) { lead_dependency_change_source }

      before do
        stub_file_updater(updated_dependency_files: [])
      end

      it "raises an exception" do
        expect { create_change }.to raise_error(Dependabot::DependabotError)
      end
    end

    context "when only support files are returned" do
      let(:change_source) { lead_dependency_change_source }
      let(:support_files) { dependency_files.select(&:support_file?) }
      let(:updated_support_files) { [support_files.last, support_files.first, support_files.last] }

      before do
        stub_file_updater(updated_dependency_files: updated_support_files)
      end

      it "warns with excluded support file names" do
        expect(Dependabot.logger)
          .to receive(:warn)
          .with(satisfy { |message|
            message.include?(support_files_only_error_message) &&
              message.include?("excluded:") &&
              message.include?("sub_dep") &&
              message.include?("sub_dep.lock") &&
              !message.include?("(and")
          })

        expect { create_change }
          .to raise_error(Dependabot::DependabotError, support_files_only_error_message)
      end
    end

    context "when support file names exceed warning limit" do
      let(:change_source) { lead_dependency_change_source }
      let(:support_files) do
        Array.new(described_class::SUPPORT_FILE_WARNING_NAME_LIMIT + 1) do |index|
          Dependabot::DependencyFile.new(
            name: "support_#{index}.txt",
            content: "content",
            directory: "/",
            support_file: true
          )
        end
      end

      before do
        stub_file_updater(updated_dependency_files: support_files)
      end

      it "warns with the listed limit and omitted count" do
        expect(Dependabot.logger)
          .to receive(:warn)
          .with(satisfy { |message|
            message.include?(support_files_only_error_message) &&
              message.include?("excluded:") &&
              message.include?("(and 1 more)")
          })

        expect { create_change }
          .to raise_error(Dependabot::DependabotError, support_files_only_error_message)
      end
    end
  end
end
