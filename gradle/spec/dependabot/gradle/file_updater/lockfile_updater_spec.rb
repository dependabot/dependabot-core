# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/gradle/file_updater"

RSpec.describe Dependabot::Gradle::FileUpdater::LockfileUpdater do
  subject(:lockfile_updater) { described_class.new(dependency_files: dependency_files) }

  let(:root_settings) do
    Dependabot::DependencyFile.new(
      name: "settings.gradle",
      directory: "/",
      content: "include(':app')\nincludeBuild('included')\n"
    )
  end

  let(:included_settings) do
    Dependabot::DependencyFile.new(
      name: "included/settings.gradle",
      directory: "/",
      content: "include(':lib')\n"
    )
  end

  let(:root_buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      directory: "/",
      content: "plugins { id 'java' }\n"
    )
  end

  let(:app_buildfile) do
    Dependabot::DependencyFile.new(
      name: "app/build.gradle",
      directory: "/",
      content: "plugins { id 'java-library' }\n"
    )
  end

  let(:included_buildfile) do
    Dependabot::DependencyFile.new(
      name: "included/build.gradle",
      directory: "/",
      content: "plugins { id 'java' }\n"
    )
  end

  let(:root_lockfile) do
    Dependabot::DependencyFile.new(
      name: "gradle.lockfile",
      directory: "/",
      content: "# root lockfile\n"
    )
  end

  let(:app_lockfile) do
    Dependabot::DependencyFile.new(
      name: "app/gradle.lockfile",
      directory: "/",
      content: "# app lockfile\n"
    )
  end

  let(:included_lockfile) do
    Dependabot::DependencyFile.new(
      name: "included/gradle.lockfile",
      directory: "/",
      content: "# included lockfile\n"
    )
  end

  let(:external_lockfile) do
    Dependabot::DependencyFile.new(
      name: "external/gradle.lockfile",
      directory: "/",
      content: "# external lockfile\n"
    )
  end

  describe "#update_lockfiles" do
    context "when the build file belongs to the root build" do
      let(:dependency_files) do
        [
          root_settings,
          root_buildfile,
          app_buildfile,
          root_lockfile,
          app_lockfile,
          external_lockfile
        ]
      end

      let(:observed_cwds) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          observed_cwds << cwd
          File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
          FileUtils.mkdir_p(File.join(cwd, "app"))
          File.write(File.join(cwd, "app/gradle.lockfile"), "# updated app lockfile\n")
        end
      end

      it "runs from the repository root and updates lockfiles in scope" do
        result = lockfile_updater.update_lockfiles(root_buildfile)

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          include("dependabotResolveAll"),
          cwd: kind_of(String)
        )
        expect(observed_cwds.last).not_to end_with("/app")
        expect(observed_cwds.last).not_to end_with("/external")

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# updated root lockfile\n")
        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# updated app lockfile\n")
        expect(result.find { |f| f.name == "external/gradle.lockfile" }.content).to eq("# external lockfile\n")
      end
    end

    context "when the build file belongs to an included build" do
      let(:dependency_files) do
        [
          root_settings,
          included_settings,
          included_buildfile,
          included_lockfile,
          external_lockfile
        ]
      end

      let(:observed_cwds) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          observed_cwds << cwd
          File.write(File.join(cwd, "gradle.lockfile"), "# updated included lockfile\n")
        end
      end

      it "runs from the included build root and updates only that root's lockfiles" do
        result = lockfile_updater.update_lockfiles(included_buildfile)

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          include("dependabotResolveAll"),
          cwd: kind_of(String)
        )
        expect(observed_cwds.last).to end_with("/included")

        expect(result.find { |f| f.name == "included/gradle.lockfile" }.content).to eq("# updated included lockfile\n")
        expect(result.find { |f| f.name == "external/gradle.lockfile" }.content).to eq("# external lockfile\n")
      end
    end

    context "when using a version catalog without a settings file" do
      let(:version_catalog) do
        Dependabot::DependencyFile.new(
          name: "gradle/libs.versions.toml",
          directory: "/",
          content: "[versions]\nfoo = \"1.0.0\"\n"
        )
      end

      let(:dependency_files) do
        [
          version_catalog,
          root_lockfile,
          app_lockfile
        ]
      end

      let(:observed_cwds) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          observed_cwds << cwd
          File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
          FileUtils.mkdir_p(File.join(cwd, "app"))
          File.write(File.join(cwd, "app/gradle.lockfile"), "# updated app lockfile\n")
        end
      end

      it "falls back to the project root and updates root-scoped lockfiles" do
        result = lockfile_updater.update_lockfiles(version_catalog)

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          include("dependabotResolveAll"),
          cwd: kind_of(String)
        )
        expect(observed_cwds.last).not_to end_with("/gradle")

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# updated root lockfile\n")
        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# updated app lockfile\n")
      end
    end

    context "when Gradle does not regenerate one of the lockfiles" do
      let(:dependency_files) { [root_settings, root_buildfile, root_lockfile, app_lockfile] }

      before do
        allow(Dependabot.logger).to receive(:warn)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
        end
      end

      it "keeps lockfiles with unchanged content" do
        result = lockfile_updater.update_lockfiles(root_buildfile)

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# updated root lockfile\n")
        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# app lockfile\n")
      end
    end

    context "when the Gradle invocation fails" do
      let(:dependency_files) { [root_settings, app_buildfile, root_lockfile, app_lockfile] }

      before do
        allow(Dependabot.logger).to receive(:error)

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "gradle failed",
                       error_context: { command: "gradle" }
                     ))
      end

      it "returns the existing files unchanged" do
        result = lockfile_updater.update_lockfiles(app_buildfile)

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# root lockfile\n")
        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# app lockfile\n")
        expect(Dependabot.logger).to have_received(:error).with(include("Failed to update lockfiles"))
      end
    end

    context "when there are no lockfiles in scope" do
      let(:dependency_files) { [root_settings, root_buildfile] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      end

      it "returns dependency files unchanged without invoking Gradle" do
        result = lockfile_updater.update_lockfiles(root_buildfile)

        expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
        expect(result).to eq(dependency_files)
      end
    end

    context "when files have a non-root source directory" do
      let(:subdir_settings) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/gradle-lockfile",
          content: "include(':app')\n"
        )
      end

      let(:subdir_buildfile) do
        Dependabot::DependencyFile.new(
          name: "app/build.gradle",
          directory: "/gradle-lockfile",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:subdir_root_lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/gradle-lockfile",
          content: "# old root lockfile\n"
        )
      end

      let(:subdir_app_lockfile) do
        Dependabot::DependencyFile.new(
          name: "app/gradle.lockfile",
          directory: "/gradle-lockfile",
          content: "# old app lockfile\n"
        )
      end

      let(:dependency_files) do
        [subdir_settings, subdir_buildfile, subdir_root_lockfile, subdir_app_lockfile]
      end

      let(:observed_cwds) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          observed_cwds << cwd
          File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
          FileUtils.mkdir_p(File.join(cwd, "app"))
          File.write(File.join(cwd, "app/gradle.lockfile"), "# updated app lockfile\n")
        end
      end

      it "resolves root_dir to the source directory and runs Gradle from there" do
        result = lockfile_updater.update_lockfiles(subdir_buildfile)

        expect(observed_cwds.last).to end_with("/gradle-lockfile")

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# updated root lockfile\n")
        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# updated app lockfile\n")
      end
    end
  end
end
