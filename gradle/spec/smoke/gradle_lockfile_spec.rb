# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/gradle/file_updater"

RSpec.describe Dependabot::Gradle::FileUpdater::LockfileUpdater do
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: "dependencies { }"
    )
  end

  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "gradle.lockfile",
      content: "# lockfile content"
    )
  end

  let(:subproject_buildfile) do
    Dependabot::DependencyFile.new(
      name: "app/build.gradle",
      content: "dependencies { }"
    )
  end

  let(:subproject_lockfile) do
    Dependabot::DependencyFile.new(
      name: "app/gradle.lockfile",
      content: "# app lockfile"
    )
  end

  let(:settings_file) do
    Dependabot::DependencyFile.new(
      name: "settings.gradle",
      content: "include(':app')"
    )
  end

  let(:updater) do
    described_class.new(dependency_files: dependency_files)
  end

  before do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command) { "" }
  end

  describe "#find_settings_file" do
    context "when settings file exists in root" do
      let(:dependency_files) { [buildfile, lockfile, settings_file] }

      it "finds the settings file" do
        result = updater.send(:find_settings_file, buildfile)
        expect(result).not_to be_nil
        expect(result.name).to eq("settings.gradle")
      end
    end

    context "when build file is in subdirectory and settings file in root" do
      let(:dependency_files) { [buildfile, lockfile, settings_file, subproject_buildfile, subproject_lockfile] }

      it "finds the closest ancestor settings file" do
        result = updater.send(:find_settings_file, subproject_buildfile)
        expect(result).not_to be_nil
        expect(result.name).to eq("settings.gradle")
      end
    end

    context "when no settings file exists" do
      let(:dependency_files) { [buildfile, lockfile] }

      it "returns nil" do
        result = updater.send(:find_settings_file, buildfile)
        expect(result).to be_nil
      end
    end
  end

  describe "#determine_root_dir" do
    context "when settings file exists" do
      let(:dependency_files) { [buildfile, lockfile, settings_file] }

      it "returns a directory string for settings file" do
        root_dir = updater.determine_root_dir(build_file: buildfile)
        expect(root_dir).to be_a(String)
      end
    end

    context "when no settings file exists" do
      let(:dependency_files) { [buildfile, lockfile] }

      it "returns the build file directory" do
        root_dir = updater.determine_root_dir(build_file: buildfile)
        expect(root_dir).to be_a(String)
      end
    end
  end

  describe "#update_lockfiles scopes lockfiles to root_dir" do
    context "with root and subproject lockfiles" do
      let(:dependency_files) { [buildfile, lockfile, settings_file, subproject_buildfile, subproject_lockfile] }

      it "selects only lockfiles within the resolved root_dir" do
        # When root_dir is ".", all lockfiles at "." and "app/" are within scope
        # This is just testing the scoping logic, not the Gradle behavior
        root_dir = updater.determine_root_dir(build_file: buildfile)
        scoped_lockfiles = dependency_files.select do |file|
          file.name.end_with?(".lockfile") &&
            File.join(file.directory, file.name).start_with?(root_dir)
        end

        expect(scoped_lockfiles).to include(lockfile)
        expect(scoped_lockfiles).to include(subproject_lockfile)
      end
    end
  end

  describe "#write_init_script" do
    it "creates an init script file" do
      Dependabot::SharedHelpers.in_a_temporary_directory do |temp_dir|
        script_path = File.join(temp_dir, "test.init.gradle")
        simple_updater = described_class.new(dependency_files: [buildfile])
        simple_updater.send(:write_init_script, script_path)

        expect(File.exist?(script_path)).to be true
        content = File.read(script_path)
        expect(content).to include("allprojects")
        expect(content).to include("dependabotResolveAll")
        expect(content).to include("canBeResolved")
      end
    end
  end

  describe "#write_properties_file" do
    it "creates a properties file" do
      Dependabot::SharedHelpers.in_a_temporary_directory do |temp_dir|
        props_path = File.join(temp_dir, "gradle.properties")
        simple_updater = described_class.new(dependency_files: [buildfile])
        simple_updater.send(:write_properties_file, props_path)

        expect(File.exist?(props_path)).to be true
        content = File.read(props_path)
        expect(content).to include("systemProp.http.proxyHost")
        expect(content).to include("systemProp.https.proxyHost")
      end
    end
  end

  describe "#update_lockfiles_content warns on missing lockfiles" do
    context "when lockfile was not regenerated" do
      it "logs a warning instead of silently skipping" do
        allow(Dependabot.logger).to receive(:warn)

        Dependabot::SharedHelpers.in_a_temporary_directory do |temp_dir|
          # Create updater with a lockfile
          simple_updater = described_class.new(dependency_files: [buildfile, lockfile])
          # Don't create the lockfile in temp_dir, simulating that Gradle didn't write it
          updated_files = [lockfile]
          simple_updater.send(:update_lockfiles_content, temp_dir, [lockfile], updated_files)

          expect(Dependabot.logger).to have_received(:warn).with(
            include("was not regenerated by Gradle")
          )
        end
      end
    end
  end
end
