# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/gradle/file_updater"

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Dependabot::Gradle::FileUpdater do
  subject(:file_updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: credentials
    )
  end

  let(:credentials) { [] }
  let(:root_buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      directory: "/",
      content: <<~GRADLE
        dependencies {
          implementation "org.apache.commons:commons-lang3:3.12.0"
        }
      GRADLE
    )
  end

  let(:app_buildfile) do
    Dependabot::DependencyFile.new(
      name: "app/build.gradle",
      directory: "/",
      content: <<~GRADLE
        dependencies {
          implementation "org.apache.commons:commons-lang3:3.12.0"
        }
      GRADLE
    )
  end

  let(:settings_file) do
    Dependabot::DependencyFile.new(
      name: "settings.gradle",
      directory: "/",
      content: "include(':app')\n"
    )
  end

  let(:root_lockfile) do
    Dependabot::DependencyFile.new(
      name: "gradle.lockfile",
      directory: "/",
      content: "# old root lockfile\n"
    )
  end

  let(:app_lockfile) do
    Dependabot::DependencyFile.new(
      name: "app/gradle.lockfile",
      directory: "/",
      content: "# old app lockfile\n"
    )
  end

  let(:dependency_files) do
    [
      root_buildfile,
      app_buildfile,
      settings_file,
      root_lockfile,
      app_lockfile
    ]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "org.apache.commons:commons-lang3",
      version: "3.13.0",
      previous_version: "3.12.0",
      requirements: [
        {
          file: "build.gradle",
          requirement: "3.13.0",
          groups: [],
          source: nil,
          metadata: nil
        },
        {
          file: "app/build.gradle",
          requirement: "3.13.0",
          groups: [],
          source: nil,
          metadata: nil
        }
      ],
      previous_requirements: [
        {
          file: "build.gradle",
          requirement: "3.12.0",
          groups: [],
          source: nil,
          metadata: nil
        },
        {
          file: "app/build.gradle",
          requirement: "3.12.0",
          groups: [],
          source: nil,
          metadata: nil
        }
      ],
      package_manager: "gradle"
    )
  end

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:gradle_lockfile_updater)
      .and_return(true)

    allow_any_instance_of(Dependabot::Gradle::FileUpdater::WrapperUpdater) # rubocop:disable RSpec/AnyInstance
      .to receive(:update_files).and_return([])

    allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
      File.write(File.join(cwd, "gradle.lockfile"), "# new root lockfile\n")
      FileUtils.mkdir_p(File.join(cwd, "app"))
      File.write(File.join(cwd, "app/gradle.lockfile"), "# new app lockfile\n")
    end
  end

  it "deduplicates lockfile updates by root and updates sibling lockfiles in one run" do
    expect(Dependabot::SharedHelpers).to receive(:run_shell_command).once.and_call_original

    updated_files = file_updater.updated_dependency_files

    expect(updated_files.find { |f| f.name == "build.gradle" }.content).to include("3.13.0")
    expect(updated_files.find { |f| f.name == "app/build.gradle" }.content).to include("3.13.0")
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
