# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/shared_helpers"
require "dependabot/gradle/file_updater/lockfile_updater"

RSpec.describe Dependabot::Gradle::FileUpdater::LockfileUpdater do
  let(:lockfile_updater) do
    described_class.new(dependency_files: dependency_files)
  end

  describe "#update_lockfiles" do
    before do
      Dependabot::Experiments.register(:gradle_lockfile_updater, true)
    end

    after do
      Dependabot::Experiments.reset!
    end

    context "when a single-module project" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: fixture("buildfiles", "basic_build.gradle")
        )
      end

      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# lockfile content"
        )
      end

      let(:dependency_files) { [buildfile, lockfile] }

      it "returns all dependency files including updated lockfile" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do
          File.write(File.join(Dir.pwd, "gradle.lockfile"), "# updated lockfile content")
        end

        result = lockfile_updater.update_lockfiles(buildfile)

        expect(result).to include(buildfile)
        updated_lockfile = result.find { |f| f.name == "gradle.lockfile" }
        expect(updated_lockfile).not_to be_nil
        expect(updated_lockfile.content).to eq("# updated lockfile content")
      end

      it "skips update when lockfile content is unchanged" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do
          File.write(File.join(Dir.pwd, "gradle.lockfile"), "# lockfile content")
        end

        result = lockfile_updater.update_lockfiles(buildfile)

        updated_lockfile = result.find { |f| f.name == "gradle.lockfile" }
        # Content unchanged, so original file object is preserved
        expect(updated_lockfile).to eq(lockfile)
      end
    end

    context "when a multi-module project with app and lib modules" do
      let(:settings_file) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: <<~GRADLE
            rootProject.name = 'multi-module-project'
            include 'app'
            include 'lib'
          GRADLE
        )
      end

      let(:root_buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: fixture("buildfiles", "basic_build.gradle")
        )
      end

      let(:root_lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# root lockfile content"
        )
      end

      let(:app_buildfile) do
        Dependabot::DependencyFile.new(
          name: "app/build.gradle",
          directory: "/",
          content: fixture("buildfiles", "basic_build.gradle")
        )
      end

      let(:app_lockfile) do
        Dependabot::DependencyFile.new(
          name: "app/gradle.lockfile",
          directory: "/",
          content: "# app lockfile content"
        )
      end

      let(:lib_buildfile) do
        Dependabot::DependencyFile.new(
          name: "lib/build.gradle",
          directory: "/",
          content: fixture("buildfiles", "basic_build.gradle")
        )
      end

      let(:lib_lockfile) do
        Dependabot::DependencyFile.new(
          name: "lib/gradle.lockfile",
          directory: "/",
          content: "# lib lockfile content"
        )
      end

      let(:dependency_files) do
        [settings_file, root_buildfile, root_lockfile, app_buildfile, app_lockfile, lib_buildfile, lib_lockfile]
      end

      it "updates all module lockfiles when invoked with a submodule build file" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do
          cwd = Dir.pwd
          File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile")
          FileUtils.mkdir_p(File.join(cwd, "app"))
          FileUtils.mkdir_p(File.join(cwd, "lib"))
          File.write(File.join(cwd, "app", "gradle.lockfile"), "# updated app lockfile")
          File.write(File.join(cwd, "lib", "gradle.lockfile"), "# updated lib lockfile")
        end

        result = lockfile_updater.update_lockfiles(app_buildfile)

        root_updated = result.find { |f| f.name == "gradle.lockfile" }
        expect(root_updated&.content).to eq("# updated root lockfile")

        app_updated = result.find { |f| f.name == "app/gradle.lockfile" }
        expect(app_updated&.content).to eq("# updated app lockfile")

        lib_updated = result.find { |f| f.name == "lib/gradle.lockfile" }
        expect(lib_updated&.content).to eq("# updated lib lockfile")
      end

      it "runs gradle from the project root (where settings.gradle lives)" do
        cwd_used = nil
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_cmd, cwd:|
          cwd_used = cwd
          File.write(File.join(cwd, "gradle.lockfile"), "# updated")
          FileUtils.mkdir_p(File.join(cwd, "app"))
          FileUtils.mkdir_p(File.join(cwd, "lib"))
          File.write(File.join(cwd, "app", "gradle.lockfile"), "# updated")
          File.write(File.join(cwd, "lib", "gradle.lockfile"), "# updated")
        end

        lockfile_updater.update_lockfiles(app_buildfile)

        # cwd should be at the project root, not inside a submodule
        expect(cwd_used).not_to be_nil
        expect(cwd_used).not_to end_with("/app")
        expect(cwd_used).not_to end_with("/lib")
      end
    end

    context "with version catalog and settings.gradle" do
      let(:settings_file) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: "rootProject.name = 'project-with-catalog'\n"
        )
      end

      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:version_catalog) do
        Dependabot::DependencyFile.new(
          name: "gradle/libs.versions.toml",
          directory: "/",
          content: "[versions]\njunit = \"4.13.2\"\n"
        )
      end

      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# lockfile content"
        )
      end

      let(:dependency_files) { [settings_file, buildfile, version_catalog, lockfile] }

      it "updates lockfile when version catalog changes" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do
          File.write(File.join(Dir.pwd, "gradle.lockfile"), "# updated after catalog change")
        end

        result = lockfile_updater.update_lockfiles(version_catalog)

        updated_lockfile = result.find { |f| f.name == "gradle.lockfile" }
        expect(updated_lockfile&.content).to eq("# updated after catalog change")
      end
    end

    context "without settings.gradle (version catalog at root)" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: "plugins { id 'java' }\n"
        )
      end

      let(:version_catalog) do
        Dependabot::DependencyFile.new(
          name: "gradle/libs.versions.toml",
          directory: "/",
          content: "[versions]\njunit = \"4.13.2\"\n"
        )
      end

      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# lockfile content"
        )
      end

      let(:dependency_files) { [buildfile, version_catalog, lockfile] }

      it "runs gradle from the job directory (project root)" do
        cwd_used = nil
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_cmd, cwd:|
          cwd_used = cwd
          File.write(File.join(cwd, "gradle.lockfile"), "# updated via catalog")
        end

        result = lockfile_updater.update_lockfiles(version_catalog)

        updated_lockfile = result.find { |f| f.name == "gradle.lockfile" }
        expect(updated_lockfile&.content).to eq("# updated via catalog")
        # Should NOT be inside gradle/ subdir
        expect(cwd_used).not_to end_with("/gradle")
      end
    end

    context "when lockfile does not exist after gradle run" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: fixture("buildfiles", "basic_build.gradle")
        )
      end

      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# lockfile content"
        )
      end

      let(:dependency_files) { [buildfile, lockfile] }

      it "gracefully skips missing lockfiles without raising" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do
          # Gradle runs but doesn't produce a lockfile (e.g., no resolvable dependencies)
          FileUtils.rm_f(File.join(Dir.pwd, "gradle.lockfile"))
        end

        result = lockfile_updater.update_lockfiles(buildfile)

        # Original file returned unchanged
        expect(result.find { |f| f.name == "gradle.lockfile" }).to eq(lockfile)
      end
    end
  end
end
