# typed: false
# frozen_string_literal: true

require "base64"

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

  let(:gradlew) do
    Dependabot::DependencyFile.new(
      name: "gradlew",
      directory: "/",
      content: "#!/bin/sh\necho wrapper\n"
    )
  end

  let(:gradle_wrapper_jar_raw) { "fake-gradle-wrapper\x00bytes" }

  let(:gradle_wrapper_jar) do
    Dependabot::DependencyFile.new(
      name: "gradle/wrapper/gradle-wrapper.jar",
      directory: "/",
      content: Base64.strict_encode64(gradle_wrapper_jar_raw),
      content_encoding: Dependabot::DependencyFile::ContentEncoding::BASE64
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
      let(:observed_commands) { [] }
      let(:observed_wrapper_executable) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, cwd:|
          observed_cwds << cwd
          observed_commands << command

          wrapper_token = command.split.first
          if wrapper_token&.include?("gradlew")
            wrapper_path = File.expand_path(wrapper_token, cwd)
            observed_wrapper_executable << File.executable?(wrapper_path)
          end

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

      it "runs the subproject dependencies task for subproject build files" do
        lockfile_updater.update_lockfiles(app_buildfile)

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          include(":app:dependencies"),
          cwd: kind_of(String)
        )
      end

      it "runs scoped tasks for every changed build file in the root" do
        lockfile_updater.update_lockfiles(root_buildfile, build_files: [root_buildfile, app_buildfile])

        expect(observed_commands.last).to include(":app:dependencies")
        expect(observed_commands.last).to include("dependabotResolveAll")
      end

      context "when the subproject uses a custom projectDir mapping" do
        let(:custom_settings) do
          Dependabot::DependencyFile.new(
            name: "settings.gradle",
            directory: "/",
            content: "include ':chrome-trace'\n" \
                     "project(':chrome-trace').projectDir = new File(rootDir, 'subprojects/chrome-trace')\n"
          )
        end
        let(:custom_buildfile) do
          Dependabot::DependencyFile.new(
            name: "build.gradle",
            directory: "/",
            content: "plugins { id 'java' }\n"
          )
        end
        let(:custom_subproject_buildfile) do
          Dependabot::DependencyFile.new(
            name: "build.gradle",
            directory: "/subprojects/chrome-trace",
            content: "plugins { id 'java' }\n"
          )
        end
        let(:custom_lockfile) do
          Dependabot::DependencyFile.new(
            name: "gradle.lockfile",
            directory: "/subprojects/chrome-trace",
            content: "# old lockfile\n"
          )
        end

        let(:dependency_files) { [custom_settings, custom_buildfile, custom_subproject_buildfile, custom_lockfile] }
        let(:observed_commands) { [] }

        before do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, cwd:|
            observed_commands << command
            File.write(File.join(cwd, "gradle.lockfile"), "# updated lockfile\n")
          end
        end

        it "falls back to dependabotResolveAll only without a project-specific task" do
          lockfile_updater.update_lockfiles(custom_subproject_buildfile)

          expect(observed_commands.last).not_to include(":subprojects:chrome-trace:dependencies")
          expect(observed_commands.last).to include("dependabotResolveAll")
        end
      end

      context "when a local gradlew script is available" do
        let(:dependency_files) do
          [
            gradlew,
            root_settings,
            root_buildfile,
            root_lockfile
          ]
        end

        let(:observed_command) { [] }
        let(:observed_wrapper_executable) { [] }

        before do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, cwd:|
            File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
            observed_command << command

            wrapper_path = File.expand_path(command.split.first, cwd)
            observed_wrapper_executable << File.executable?(wrapper_path)
          end
        end

        it "prefers the local wrapper executable" do
          lockfile_updater.update_lockfiles(root_buildfile)

          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          expect(observed_command.last).to include("./gradlew")
          expect(observed_wrapper_executable.last).to be(true)
        end

        it "returns existing files unchanged when wrapper execution fails" do
          allow(Dependabot.logger).to receive(:error)

          allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
            .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                         message: "Error: Invalid or corrupt jarfile gradle/wrapper/gradle-wrapper.jar",
                         error_context: { command: "./gradlew" }
                       ))

          result = lockfile_updater.update_lockfiles(root_buildfile)

          expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# root lockfile\n")
          expect(Dependabot.logger).to have_received(:error).with(include("Failed to update lockfiles"))
        end

        it "retries daemon failures through a larger heap size before succeeding" do
          attempts = []

          allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
            properties_content = File.read(File.join(cwd, "gradle.properties"))
            attempts << properties_content[/^org\.gradle\.jvmargs=(.*)$/, 1]

            if attempts.length < 2
              raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                message: "Gradle build daemon disappeared unexpectedly",
                error_context: { process_exit_value: 1 }
              )
            end

            File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
          end

          result = lockfile_updater.update_lockfiles(root_buildfile)

          expect(attempts).to eq(
            [
              "-Xmx1536m -Dfile.encoding=UTF-8",
              "-Xmx2048m -Dfile.encoding=UTF-8"
            ]
          )
          expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# updated root lockfile\n")
        end
      end

      context "when gradle-wrapper.jar is base64 encoded" do
        let(:dependency_files) do
          [
            gradlew,
            gradle_wrapper_jar,
            root_settings,
            root_buildfile,
            root_lockfile
          ]
        end

        let(:observed_wrapper_jar_content) { [] }

        before do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
            wrapper_jar_path = File.join(cwd, "gradle/wrapper/gradle-wrapper.jar")
            observed_wrapper_jar_content << File.binread(wrapper_jar_path)
            File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
          end
        end

        it "writes decoded binary wrapper jar content to disk" do
          lockfile_updater.update_lockfiles(root_buildfile)

          expect(observed_wrapper_jar_content.last).to eq(gradle_wrapper_jar_raw)
        end
      end

      context "when a local gradlew script is not available" do
        let(:dependency_files) do
          [
            root_settings,
            root_buildfile,
            root_lockfile
          ]
        end

        let(:observed_command) { [] }

        before do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, cwd:|
            File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
            observed_command << command
          end
        end

        it "falls back to system gradle" do
          lockfile_updater.update_lockfiles(root_buildfile)

          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          expect(observed_command.last).to start_with("gradle ")
        end
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
      let(:observed_commands) { [] }
      let(:observed_wrapper_executable) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, cwd:|
          observed_cwds << cwd
          observed_commands << command

          wrapper_token = command.split.first
          if wrapper_token&.include?("gradlew")
            wrapper_path = File.expand_path(wrapper_token, cwd)
            observed_wrapper_executable << File.executable?(wrapper_path)
          end

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

    context "when a project dependency needs another project's toolchain" do
      # Resolving :app reaches into :lib's compile task, so every project has to be prepared before
      # anything is resolved. Offline, like the cases below.
      let(:mp_settings) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          directory: "/",
          content: "rootProject.name = 'mp'\ninclude('app', 'lib')\n"
        )
      end
      let(:mp_app) do
        Dependabot::DependencyFile.new(
          name: "app/build.gradle",
          directory: "/",
          content: <<~GRADLE
            plugins { id 'java' }

            java { toolchain { languageVersion = JavaLanguageVersion.of(99) } }

            dependencyLocking { lockAllConfigurations() }

            repositories { maven { url = uri("../local-repo") } }

            dependencies {
              implementation project(':lib')
              implementation "com.example:dummy:1.0"
            }
          GRADLE
        )
      end
      let(:mp_lib) do
        Dependabot::DependencyFile.new(
          name: "lib/build.gradle",
          directory: "/",
          content: <<~GRADLE
            plugins { id 'java' }

            java { toolchain { languageVersion = JavaLanguageVersion.of(99) } }

            dependencyLocking { lockAllConfigurations() }
          GRADLE
        )
      end
      let(:mp_lockfile) do
        Dependabot::DependencyFile.new(
          name: "app/gradle.lockfile", directory: "/", content: "# stale\n"
        )
      end
      let(:mp_pom) do
        Dependabot::DependencyFile.new(
          name: "local-repo/com/example/dummy/1.0/dummy-1.0.pom",
          directory: "/",
          content: <<~POM
            <project>
              <modelVersion>4.0.0</modelVersion>
              <groupId>com.example</groupId>
              <artifactId>dummy</artifactId>
              <version>1.0</version>
            </project>
          POM
        )
      end
      let(:dependency_files) { [mp_settings, mp_app, mp_lib, mp_pom, mp_lockfile] }

      it "resolves the dependent project" do
        updated = lockfile_updater.update_lockfiles(mp_app)

        expect(updated.find { |f| f.name == "app/gradle.lockfile" }.content)
          .to include("com.example:dummy:1.0")
      end
    end

    context "when the build has the configuration cache enabled" do
      # Resolving from a task action is what the configuration cache rejects, so this covers that
      # the resolution happens elsewhere. Offline, like the toolchain case below.
      let(:cc_buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: <<~GRADLE
            plugins { id 'java' }

            dependencyLocking { lockAllConfigurations() }

            repositories { maven { url = uri("local-repo") } }

            dependencies { implementation "com.example:dummy:1.0" }
          GRADLE
        )
      end
      let(:cc_properties) do
        Dependabot::DependencyFile.new(
          name: "gradle.properties",
          directory: "/",
          content: "org.gradle.configuration-cache=true\n"
        )
      end
      let(:cc_pom) do
        Dependabot::DependencyFile.new(
          name: "local-repo/com/example/dummy/1.0/dummy-1.0.pom",
          directory: "/",
          content: <<~POM
            <project>
              <modelVersion>4.0.0</modelVersion>
              <groupId>com.example</groupId>
              <artifactId>dummy</artifactId>
              <version>1.0</version>
            </project>
          POM
        )
      end
      let(:cc_lockfile) do
        Dependabot::DependencyFile.new(name: "gradle.lockfile", directory: "/", content: "# stale\n")
      end
      let(:dependency_files) { [cc_buildfile, cc_properties, cc_pom, cc_lockfile] }
      let(:observed_commands) { [] }

      before do
        original = Dependabot::SharedHelpers.method(:run_shell_command)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, **kwargs|
          observed_commands << command
          original.call(command, **kwargs)
        end
      end

      it "regenerates the lockfile with the cache left enabled" do
        updated = lockfile_updater.update_lockfiles(cc_buildfile)

        expect(observed_commands.last).not_to include("--no-configuration-cache")
        expect(updated.find { |f| f.name == "gradle.lockfile" }.content)
          .to include("com.example:dummy:1.0")
      end
    end

    context "when the project requests a Java toolchain that is not installed" do
      # Real Gradle, offline: java is a core plugin and the dependency comes from the file
      # repository below, so the toolchain lookup is the only thing that can fail.
      let(:toolchain_buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle",
          directory: "/",
          content: <<~GRADLE
            plugins { id 'java' }

            java {
              toolchain {
                languageVersion = JavaLanguageVersion.of(99)
              }
            }

            dependencyLocking { lockAllConfigurations() }

            repositories { maven { url = uri("local-repo") } }

            dependencies { implementation "com.example:dummy:1.0" }
          GRADLE
        )
      end
      # Something to resolve is required: without it Gradle never computes the javaCompiler.
      let(:toolchain_pom) do
        Dependabot::DependencyFile.new(
          name: "local-repo/com/example/dummy/1.0/dummy-1.0.pom",
          directory: "/",
          content: <<~POM
            <project>
              <modelVersion>4.0.0</modelVersion>
              <groupId>com.example</groupId>
              <artifactId>dummy</artifactId>
              <version>1.0</version>
            </project>
          POM
        )
      end
      let(:toolchain_lockfile) do
        Dependabot::DependencyFile.new(
          name: "gradle.lockfile",
          directory: "/",
          content: "# stale lockfile\n"
        )
      end
      let(:dependency_files) { [toolchain_buildfile, toolchain_pom, toolchain_lockfile] }

      it "falls back to the running JVM and resolves" do
        updated = lockfile_updater.update_lockfiles(toolchain_buildfile)

        expect(updated.find { |f| f.name == "gradle.lockfile" }.content)
          .to include("com.example:dummy:1.0")
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

      it "retries with larger jvmargs when daemon disappears" do
        observed_properties = []
        allow(Dependabot.logger).to receive(:warn)

        call_count = 0
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          properties_path = File.join(cwd, "gradle.properties")
          observed_properties << File.read(properties_path)

          call_count += 1
          if call_count == 1
            raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "Gradle build daemon disappeared unexpectedly",
              error_context: { command: "gradle" }
            )
          end

          File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
          FileUtils.mkdir_p(File.join(cwd, "app"))
          File.write(File.join(cwd, "app/gradle.lockfile"), "# updated app lockfile\n")
        end

        result = lockfile_updater.update_lockfiles(app_buildfile)

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# updated root lockfile\n")
        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# updated app lockfile\n")
        expect(observed_properties.first).to include("org.gradle.jvmargs=-Xmx1536m -Dfile.encoding=UTF-8")
        expect(observed_properties.last).to include("org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8")
        expect(Dependabot.logger).to have_received(:warn).with(include("Retrying once"))
      end

      it "retries with larger jvmargs when the subprocess is killed" do
        observed_properties = []
        allow(Dependabot.logger).to receive(:warn)

        call_count = 0
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          properties_path = File.join(cwd, "gradle.properties")
          observed_properties << File.read(properties_path)

          call_count += 1
          if call_count == 1
            raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "Gradle exited",
              error_context: {
                command: "gradle",
                process_termsig: Dependabot::SharedHelpers::SIGKILL
              }
            )
          end

          File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
          FileUtils.mkdir_p(File.join(cwd, "app"))
          File.write(File.join(cwd, "app/gradle.lockfile"), "# updated app lockfile\n")
        end

        result = lockfile_updater.update_lockfiles(app_buildfile)

        expect(result.find { |f| f.name == "gradle.lockfile" }.content).to eq("# updated root lockfile\n")
        expect(result.find { |f| f.name == "app/gradle.lockfile" }.content).to eq("# updated app lockfile\n")
        expect(observed_properties.first).to include("org.gradle.jvmargs=-Xmx1536m -Dfile.encoding=UTF-8")
        expect(observed_properties.last).to include("org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8")
        expect(Dependabot.logger).to have_received(:warn).with(include("Retrying once"))
      end

      it "does not retry failures that only mention signal-related words" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "Dependency signaling mechanism failed after a killed resolution",
                       error_context: { command: "gradle" }
                     ))

        lockfile_updater.update_lockfiles(app_buildfile)

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
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

    context "when a gradle.properties file is present" do
      let(:gradle_properties) do
        Dependabot::DependencyFile.new(
          name: "gradle.properties",
          directory: "/",
          content: "GROUP=com.example\nVERSION=1.0.0\n"
        )
      end

      let(:dependency_files) do
        [root_settings, root_buildfile, root_lockfile, gradle_properties]
      end

      let(:observed_properties) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          properties_path = File.join(cwd, "gradle.properties")
          observed_properties << File.read(properties_path) if File.exist?(properties_path)
          File.write(File.join(cwd, "gradle.lockfile"), "# updated lockfile\n")
        end
      end

      it "preserves existing gradle.properties content and appends proxy settings" do
        allow(Dir).to receive(:glob).with("/usr/lib/jvm/java-*-openjdk-*")
                                    .and_return(["/usr/lib/jvm/java-17-openjdk-arm64"])

        lockfile_updater.update_lockfiles(root_buildfile)

        expect(observed_properties.last).to include("GROUP=com.example")
        expect(observed_properties.last).to include("VERSION=1.0.0")
        expect(observed_properties.last).to include("org.gradle.jvmargs=-Xmx1536m -Dfile.encoding=UTF-8")
        expect(observed_properties.last).to include("org.gradle.workers.max=1")
        expect(observed_properties.last).to include("org.gradle.java.installations.auto-download=false")
        expect(observed_properties.last).to include(
          "org.gradle.java.installations.paths=/usr/lib/jvm/java-17-openjdk-arm64"
        )
        expect(observed_properties.last).to include("kotlin.compiler.execution.strategy=in-process")
        expect(observed_properties.last).to include("systemProp.http.proxyHost=")
      end

      it "does not pass org.gradle.jvmargs via command-line" do
        observed_commands = []

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, cwd:|
          observed_commands << command
          File.write(File.join(cwd, "gradle.lockfile"), "# updated lockfile\n")
        end

        lockfile_updater.update_lockfiles(root_buildfile)

        expect(observed_commands.last).not_to include("-Dorg.gradle.jvmargs")
      end

      context "when gradle.properties already sets org.gradle.jvmargs" do
        let(:gradle_properties) do
          Dependabot::DependencyFile.new(
            name: "gradle.properties",
            directory: "/",
            content: "GROUP=com.example\norg.gradle.jvmargs=--add-opens java.base/java.lang=ALL-UNNAMED\n"
          )
        end

        it "preserves the existing jvmargs alongside the required overrides" do
          lockfile_updater.update_lockfiles(root_buildfile)

          jvmargs_line = observed_properties.last.lines.find { |line| line.start_with?("org.gradle.jvmargs=") }

          expect(jvmargs_line).to include("--add-opens java.base/java.lang=ALL-UNNAMED")
          expect(jvmargs_line).to include("-Xmx1536m -Dfile.encoding=UTF-8")
          expect(observed_properties.last.scan(/^org\.gradle\.jvmargs=/).size).to eq(1)
        end
      end

      it "generates an init script that resolves project configurations" do
        observed_init_script = nil

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          init_script_path = File.join(cwd, "dependabot-locking.init.gradle")
          observed_init_script = File.read(init_script_path)
          File.write(File.join(cwd, "gradle.lockfile"), "# updated lockfile\n")
        end

        lockfile_updater.update_lockfiles(root_buildfile)

        expect(observed_init_script).to include("projectsEvaluated {")
        expect(observed_init_script).to include("configurations.findAll")
        expect(observed_init_script).to include("it.resolutionStrategy.dependencyLockingEnabled")
        expect(observed_init_script).to include("it.allDependencies.any")
        expect(observed_init_script).to include("dependency instanceof org.gradle.api.artifacts.ModuleDependency")
        expect(observed_init_script).to include(".each { it.incoming.resolutionResult.allDependencies }")
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
      let(:observed_commands) { [] }
      let(:observed_wrapper_executable) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, cwd:|
          observed_cwds << cwd
          observed_commands << command

          wrapper_token = command.split.first
          if wrapper_token&.include?("gradlew")
            wrapper_path = File.expand_path(wrapper_token, cwd)
            observed_wrapper_executable << File.executable?(wrapper_path)
          end

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

      it "runs the scoped subproject dependencies task from the source directory" do
        lockfile_updater.update_lockfiles(subdir_buildfile)

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          include(":app:dependencies"),
          cwd: kind_of(String)
        )
      end

      context "when gradlew exists at the repository root" do
        let(:dependency_files) do
          [gradlew, subdir_settings, subdir_buildfile, subdir_root_lockfile, subdir_app_lockfile]
        end

        it "uses the parent-directory wrapper script" do
          lockfile_updater.update_lockfiles(subdir_buildfile)

          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          expect(observed_commands.last).to start_with("../gradlew ")
          expect(observed_wrapper_executable.last).to be(true)
        end

        it "does not execute wrappers outside the temporary repository root" do
          require "tmpdir"

          outside_root = Dir.mktmpdir("outside-gradle-wrapper")
          outside_wrapper = File.join(outside_root, "gradlew")
          File.write(outside_wrapper, "#!/bin/sh\necho outside\n")
          FileUtils.chmod("+x", outside_wrapper)

          begin
            stub_const("Dependabot::Utils::BUMP_TMP_DIR_PATH", outside_root)

            allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, cwd:|
              observed_commands << command
              File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
              FileUtils.mkdir_p(File.join(cwd, "app"))
              File.write(File.join(cwd, "app/gradle.lockfile"), "# updated app lockfile\n")
            end

            updater = described_class.new(
              dependency_files: [subdir_settings, subdir_buildfile, subdir_root_lockfile, subdir_app_lockfile]
            )
            updater.update_lockfiles(subdir_buildfile)

            expect(observed_commands.last).to start_with("gradle ")
          ensure
            FileUtils.rm_rf(outside_root)
          end
        end

        it "falls back to system gradle when the build path escapes the temporary workspace" do
          require "tmpdir"

          outside_root = Dir.mktmpdir("outside-gradle-wrapper")
          outside_wrapper = File.join(outside_root, "gradlew")
          File.write(outside_wrapper, "#!/bin/sh\necho outside\n")
          FileUtils.chmod("+x", outside_wrapper)

          escaped_settings = Dependabot::DependencyFile.new(
            name: "settings.gradle",
            directory: "/gradle-lockfile/sub/../../../../shared",
            content: "include(':app')\n"
          )

          escaped_buildfile = Dependabot::DependencyFile.new(
            name: "app/build.gradle",
            directory: "/gradle-lockfile/sub/../../../../shared",
            content: "plugins { id 'java' }\n"
          )

          escaped_root_lockfile = Dependabot::DependencyFile.new(
            name: "gradle.lockfile",
            directory: "/gradle-lockfile/sub/../../../../shared",
            content: "# old root lockfile\n"
          )

          escaped_app_lockfile = Dependabot::DependencyFile.new(
            name: "app/gradle.lockfile",
            directory: "/gradle-lockfile/sub/../../../../shared",
            content: "# old app lockfile\n"
          )

          begin
            stub_const("Dependabot::Utils::BUMP_TMP_DIR_PATH", outside_root)

            allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, cwd:|
              observed_commands << command
              File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
              FileUtils.mkdir_p(File.join(cwd, "app"))
              File.write(File.join(cwd, "app/gradle.lockfile"), "# updated app lockfile\n")
            end

            updater = described_class.new(
              dependency_files: [escaped_settings, escaped_buildfile, escaped_root_lockfile, escaped_app_lockfile]
            )
            updater.update_lockfiles(escaped_buildfile)

            expect(observed_commands.last).to start_with("gradle ")
          ensure
            FileUtils.rm_rf(outside_root)
          end
        end
      end

      context "when the build path contains parent traversal" do
        let(:traversal_settings) do
          Dependabot::DependencyFile.new(
            name: "settings.gradle",
            directory: "/gradle-lockfile/sub/../../build-logic",
            content: "include(':app')\n"
          )
        end

        let(:traversal_buildfile) do
          Dependabot::DependencyFile.new(
            name: "app/build.gradle",
            directory: "/gradle-lockfile/sub/../../build-logic",
            content: "plugins { id 'java' }\n"
          )
        end

        let(:traversal_root_lockfile) do
          Dependabot::DependencyFile.new(
            name: "gradle.lockfile",
            directory: "/gradle-lockfile/sub/../../build-logic",
            content: "# old root lockfile\n"
          )
        end

        let(:traversal_app_lockfile) do
          Dependabot::DependencyFile.new(
            name: "app/gradle.lockfile",
            directory: "/gradle-lockfile/sub/../../build-logic",
            content: "# old app lockfile\n"
          )
        end

        let(:sibling_gradlew) do
          Dependabot::DependencyFile.new(
            name: "gradlew",
            directory: "/gradle-lockfile/sub",
            content: "#!/bin/sh\necho sibling wrapper\n"
          )
        end

        let(:dependency_files) do
          [sibling_gradlew, traversal_settings, traversal_buildfile, traversal_root_lockfile, traversal_app_lockfile]
        end

        let(:observed_commands) { [] }

        before do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, cwd:|
            observed_commands << command
            File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
            FileUtils.mkdir_p(File.join(cwd, "app"))
            File.write(File.join(cwd, "app/gradle.lockfile"), "# updated app lockfile\n")
          end
        end

        it "ignores wrappers that are only reachable through lexical parent traversal" do
          lockfile_updater.update_lockfiles(traversal_buildfile)

          expect(observed_commands.last).to start_with("gradle ")
        end
      end
    end

    context "when a full repo checkout path is available" do
      subject(:lockfile_updater) do
        described_class.new(dependency_files: dependency_files, repo_contents_path: repo_dir)
      end

      let(:dependency_files) { [root_settings, root_buildfile, root_lockfile] }
      let(:repo_dir) { Dir.mktmpdir("dependabot-gradle-repo") }

      before do
        plugin_source_path = File.join(
          repo_dir,
          "build-logic/convention/src/main/kotlin/com/nice/cxonechat/AndroidLibraryConventionsPlugin.kt"
        )
        FileUtils.mkdir_p(File.dirname(plugin_source_path))
        File.write(plugin_source_path, "package com.nice.cxonechat\n")

        git_marker_path = File.join(repo_dir, ".git", "marker")
        FileUtils.mkdir_p(File.dirname(git_marker_path))
        File.write(git_marker_path, "present via symlink\n")
      end

      after do
        FileUtils.rm_rf(repo_dir)
      end

      it "copies repository files into the temporary execution directory" do
        observed_plugin_files = []
        observed_git_symlinks = []

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |_command, cwd:|
          observed_plugin_files << File.exist?(
            File.join(
              cwd,
              "build-logic/convention/src/main/kotlin/com/nice/cxonechat/AndroidLibraryConventionsPlugin.kt"
            )
          )
          # `.git` is symlinked (not copied) so that convention plugins which shell out to
          # `git` (e.g. for version derivation) keep working without duplicating the history.
          observed_git_symlinks << File.symlink?(File.join(cwd, ".git"))
          File.write(File.join(cwd, "gradle.lockfile"), "# updated root lockfile\n")
        end

        lockfile_updater.update_lockfiles(root_buildfile)

        expect(observed_plugin_files.last).to be(true)
        expect(observed_git_symlinks.last).to be(true)
        expect(File.exist?(File.join(repo_dir, ".git", "marker"))).to be(true)
      end

      it "propagates repository copy failures" do
        allow(FileUtils).to receive(:cp_r).and_raise(Errno::ENOSPC, "No space left on device")

        expect { lockfile_updater.update_lockfiles(root_buildfile) }.to raise_error(Errno::ENOSPC)
      end
    end
  end
end
