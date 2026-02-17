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
        file_updater_class = class_double(Dependabot::Bundler::FileUpdater)
        file_updater = instance_double(
          Dependabot::Bundler::FileUpdater,
          updated_dependency_files: dependency_files,
          notices: []
        )
        allow(Dependabot::FileUpdaters).to receive(:for_package_manager)
          .with("bundler")
          .and_return(file_updater_class)
        allow(file_updater_class).to receive(:new).and_return(file_updater)

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
        file_updater_class = class_double(Dependabot::Bundler::FileUpdater)
        file_updater = instance_double(
          Dependabot::Bundler::FileUpdater,
          updated_dependency_files: [],
          notices: []
        )
        allow(Dependabot::FileUpdaters).to receive(:for_package_manager)
          .with("bundler")
          .and_return(file_updater_class)
        allow(file_updater_class).to receive(:new).and_return(file_updater)
      end

      it "raises an exception with diagnostic dependency details" do
        expect { create_change }
          .to raise_error(
            Dependabot::DependabotError,
            "FileUpdater failed to update any files for: dummy-pkg-b (1.1.0 → 1.2.0)"
          )
      end
    end

    context "when only support files are returned" do
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
        support_files = dependency_files.select(&:support_file?)
        file_updater_class = class_double(Dependabot::Bundler::FileUpdater)
        file_updater = instance_double(
          Dependabot::Bundler::FileUpdater,
          updated_dependency_files: support_files,
          notices: []
        )
        allow(Dependabot::FileUpdaters).to receive(:for_package_manager)
          .with("bundler")
          .and_return(file_updater_class)
        allow(file_updater_class).to receive(:new).and_return(file_updater)
      end

      it "logs a warning and raises a diagnostic error" do
        expect(Dependabot.logger).to receive(:warn).with(
          "FileUpdater returned only support files which were excluded: sub_dep, sub_dep.lock"
        )

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
          Dependabot::Dependency.new(
            name: "dummy-pkg-a",
            package_manager: "bundler",
            version: "2.0.0",
            previous_version: "1.9.0",
            requirements: [
              {
                file: "Gemfile",
                requirement: "~> 2.0.0",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "Gemfile",
                requirement: "~> 1.9.0",
                groups: [],
                source: nil
              }
            ]
          ),
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

      let(:change_source) do
        Dependabot::DependencyGroup.new(name: "dummy-pkg-*", rules: { patterns: ["dummy-pkg-*"] })
      end

      before do
        file_updater_class = class_double(Dependabot::Bundler::FileUpdater)
        file_updater = instance_double(
          Dependabot::Bundler::FileUpdater,
          updated_dependency_files: [],
          notices: []
        )
        allow(Dependabot::FileUpdaters).to receive(:for_package_manager)
          .with("bundler")
          .and_return(file_updater_class)
        allow(file_updater_class).to receive(:new).and_return(file_updater)
      end

      it "raises an exception listing dependency names" do
        expect { create_change }
          .to raise_error(
            Dependabot::DependabotError,
            "FileUpdater failed to update any files for: dummy-pkg-a, dummy-pkg-b"
          )
      end
    end
  end
end
