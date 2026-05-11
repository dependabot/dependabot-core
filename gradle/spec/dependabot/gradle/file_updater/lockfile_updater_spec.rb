# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/gradle/file_updater"

RSpec.describe Dependabot::Gradle::FileUpdater::LockfileUpdater do
  subject(:lockfile_updater) { described_class.new(dependency_files: dependency_files) }

  # Shared file stubs ---------------------------------------------------------

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

  # ---------------------------------------------------------------------------

  describe "#update_lockfiles" do
    context "when the build file belongs to the root build" do
      let(:dependency_files) do
        [root_settings, root_buildfile, app_buildfile, root_lockfile, app_lockfile, included_lockfile]
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

      it "runs from the repository root, not from a subproject directory" do
        lockfile_updater.update_lockfiles(root_buildfile)

        expect(observed_cwds.last).not_to end_with("/app")
        expect(observed_cwds.last).not_to end_with("/included")
      end

      it "invokes gradle with the init-script task and --write-locks" do
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          include("dependabotResolveAll") & include("--write-locks"),
          cwd: kind_of(String)
        )
        lockfile_updater.update_lockfiles(root_buildfile)
      end

      it "updates lockfiles that belong to the root build" do
        result = lockfile_updater.update_lockfiles(root_buildfile)

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# updated root lockfile\n")
        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# updated app lockfile\n")
      end

      it "does not update the included build lockfile from the root run" do
        result = lockfile_updater.update_lockfiles(root_buildfile)

        # included/gradle.lockfile was not written by the mock (intentionally),
        # so it should be preserved unchanged.
        expect(result.find { |f| f.name == "included/gradle.lockfile" }.content).to eq("# included lockfile\n")
      end
    end

    context "when the build file belongs to an included/composite build" do
      let(:dependency_files) do
        [root_settings, included_settings, included_buildfile, included_lockfile, root_lockfile]
      end

      let(:observed_cwds) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          observed_cwds << cwd
          File.write(File.join(cwd, "gradle.lockfile"), "# updated included lockfile\n")
        end
      end

      it "runs from the included build root, not the repository root" do
        lockfile_updater.update_lockfiles(included_buildfile)

        expect(observed_cwds.last).to end_with("/included")
      end

      it "updates only the included build's lockfiles" do
        result = lockfile_updater.update_lockfiles(included_buildfile)

        expect(result.find { |f| f.name == "included/gradle.lockfile" }.content)
          .to eq("# updated included lockfile\n")
        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# root lockfile\n")
      end
    end

    context "when using a version catalog (libs.versions.toml) without a settings file" do
      let(:version_catalog) do
        Dependabot::DependencyFile.new(
          name: "gradle/libs.versions.toml",
          directory: "/",
          content: "[versions]\nfoo = \"1.0.0\"\n"
        )
      end

      let(:dependency_files) { [version_catalog, root_lockfile, app_lockfile] }

      let(:observed_cwds) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          observed_cwds << cwd
          File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
          FileUtils.mkdir_p(File.join(cwd, "app"))
          File.write(File.join(cwd, "app/gradle.lockfile"), "# updated app lockfile\n")
        end
      end

      it "runs from the project root, not the gradle/ subdirectory" do
        lockfile_updater.update_lockfiles(version_catalog)

        expect(observed_cwds.last).not_to end_with("/gradle")
      end

      it "updates lockfiles relative to the project root" do
        result = lockfile_updater.update_lockfiles(version_catalog)

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# updated root lockfile\n")
        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# updated app lockfile\n")
      end
    end

    context "when Gradle does not regenerate a lockfile after a successful run" do
      let(:dependency_files) { [root_settings, root_buildfile, root_lockfile, app_lockfile] }

      before do
        allow(Dependabot.logger).to receive(:warn)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
          # Simulate Gradle dropping the lockfile (e.g. configuration no longer locked).
          FileUtils.rm_f(File.join(cwd, "app/gradle.lockfile"))
        end
      end

      it "updates the regenerated lockfile" do
        result = lockfile_updater.update_lockfiles(root_buildfile)

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# updated root lockfile\n")
      end

      it "preserves the lockfile that Gradle removed" do
        result = lockfile_updater.update_lockfiles(root_buildfile)

        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# app lockfile\n")
      end

      it "logs a warning for the removed lockfile" do
        lockfile_updater.update_lockfiles(root_buildfile)

        expect(Dependabot.logger).to have_received(:warn).with(include("app/gradle.lockfile"))
      end
    end

    context "when the Gradle invocation fails" do
      let(:dependency_files) { [root_settings, root_buildfile, root_lockfile, app_lockfile] }

      before do
        allow(Dependabot.logger).to receive(:error)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "gradle failed",
                       error_context: { command: "gradle" }
                     ))
      end

      it "returns all dependency files unchanged" do
        result = lockfile_updater.update_lockfiles(root_buildfile)

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# root lockfile\n")
        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# app lockfile\n")
      end

      it "logs the error" do
        lockfile_updater.update_lockfiles(root_buildfile)

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

    context "when files have a non-root job source directory" do
      let(:subdir_settings) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/gradle-project",
          content: "include(':app')\n"
        )
      end

      let(:subdir_app_buildfile) do
        Dependabot::DependencyFile.new(
          name: "app/build.gradle",
          directory: "/gradle-project",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:subdir_root_lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/gradle-project",
          content: "# old root lockfile\n"
        )
      end

      let(:subdir_app_lockfile) do
        Dependabot::DependencyFile.new(
          name: "app/gradle.lockfile",
          directory: "/gradle-project",
          content: "# old app lockfile\n"
        )
      end

      let(:dependency_files) { [subdir_settings, subdir_app_buildfile, subdir_root_lockfile, subdir_app_lockfile] }

      let(:observed_cwds) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          observed_cwds << cwd
          File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
          FileUtils.mkdir_p(File.join(cwd, "app"))
          File.write(File.join(cwd, "app/gradle.lockfile"), "# updated app lockfile\n")
        end
      end

      it "runs Gradle from the source-directory root, not from an inner subpath" do
        lockfile_updater.update_lockfiles(subdir_app_buildfile)

        expect(observed_cwds.last).to end_with("/gradle-project")
      end

      it "updates lockfiles under the source directory" do
        result = lockfile_updater.update_lockfiles(subdir_app_buildfile)

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# updated root lockfile\n")
        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# updated app lockfile\n")
      end
    end
  end
end
