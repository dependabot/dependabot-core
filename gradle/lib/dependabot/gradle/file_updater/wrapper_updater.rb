# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "base64"
require "shellwords"
require "pathname"

require "dependabot/gradle/distributions"
require "dependabot/gradle/version"

module Dependabot
  module Gradle
    class FileUpdater
      class WrapperUpdater
        extend T::Sig
        include Dependabot::Gradle::Distributions

        require_relative "wrapper/command_builder"
        require_relative "wrapper/executing_version_detector"
        require_relative "wrapper/properties_document"
        require_relative "wrapper/properties_reconciler"

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile], dependency: Dependabot::Dependency).void }
        def initialize(dependency_files:, dependency:)
          @dependency_files = dependency_files
          @dependency = dependency
          @target_files = T.let(
            %w(
              /gradlew
              /gradlew.bat
              /gradle/wrapper/gradle-wrapper.properties
              /gradle/wrapper/gradle-wrapper.jar
            ),
            T::Array[String]
          )
          @build_files = T.let(
            %w(
              build.gradle
              build.gradle.kts
              settings.gradle
              settings.gradle.kts
            ),
            T::Array[String]
          )
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        sig { params(build_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::DependencyFile]) }
        def update_files(build_file)
          # We only run this updater if it's a distribution dependency
          return [] unless Distributions.distribution_requirements?(dependency.requirements)

          local_files = local_wrapper_files(build_file)

          # If we don't have any files in the build files don't generate one
          return [] unless local_files.any?

          # we only run this updater if the build file has a requirement for this dependency
          target_requirements = dependency.requirements.select do |req|
            T.let(req[:file], String) == build_file.name
          end
          return [] unless target_requirements.any?

          updated_files = dependency_files.dup
          SharedHelpers.in_a_temporary_directory do |temp_dir|
            populate_temp_directory(temp_dir)
            cwd = File.join(temp_dir, base_path(build_file))

            has_local_script = File.exist?(File.join(cwd, "./gradlew"))

            Dir.chdir(cwd) do
              FileUtils.chmod("+x", "./gradlew") if has_local_script

              properties_file = File.join(cwd, "gradle/wrapper/gradle-wrapper.properties")
              original_properties_content = read_file(properties_file)
              original_document = original_properties_content && Wrapper::PropertiesDocument.parse(original_properties_content)
              env = { "JAVA_OPTS" => proxy_args.join(" ") } # set proxy for gradle execution

              command = local_wrapper_command(has_local_script, target_requirements, original_document, cwd, env)

              begin
                # first attempt: run the wrapper task via the local Gradle wrapper (if present)
                # `gradle-wrapper.jar` might not be compatible with the host's Java version or
                # the `gradlew` script may be corrupted, so we try and fall back to system Gradle before giving up
                SharedHelpers.run_shell_command(command, cwd: cwd, env: env)
              rescue SharedHelpers::HelperSubprocessFailed => e
                raise e unless has_local_script # already failed with system one, there is no point to retry

                Dependabot.logger.warn("Running #{command} failed, retrying first with system Gradle: #{e.message}")

                # second attempt: run the wrapper task via system gradle and then retry via local wrapper.
                # The system Gradle may be a different (often older) version than the wrapper, so we rebuild
                # the command against its detected version to avoid passing unsupported, version-gated flags.
                system_command = system_wrapper_command(target_requirements, original_document, cwd, env)
                SharedHelpers.run_shell_command(system_command, cwd: cwd, env: env) # run via system gradle
                SharedHelpers.run_shell_command(command, cwd: cwd, env: env) # retry via local wrapper
              end

              # Gradle's wrapper task regenerates gradle-wrapper.properties from hardcoded defaults
              # (https://github.com/gradle/gradle/issues/36172), discarding comments, ordering, custom
              # keys and user-customized values. Reconcile the regenerated file back onto the user's
              # original so only the version-bump keys change.
              reconcile_properties(properties_file, original_properties_content)

              update_files_content(temp_dir, local_files, updated_files)
            rescue SharedHelpers::HelperSubprocessFailed => e
              Dependabot.logger.error("Failed to update files: #{e.message}")
              return updated_files
            end
          end
          updated_files
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        private

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def target_file?(file)
          @target_files.any? { |r| "/#{file.name}".end_with?(r) }
        end

        sig { params(build_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::DependencyFile]) }
        def local_wrapper_files(build_file)
          wrapper_root = wrapper_root_for(build_file)

          dependency_files.select do |file|
            file.directory == build_file.directory && target_file_for_wrapper_root?(file, wrapper_root)
          end
        end

        sig { params(file: Dependabot::DependencyFile, wrapper_root: String).returns(T::Boolean) }
        def target_file_for_wrapper_root?(file, wrapper_root)
          @target_files.any? do |target_file|
            target_path = target_file.delete_prefix("/")
            expected_path = wrapper_root.empty? ? target_path : File.join(wrapper_root, target_path)
            file_path(file) == Pathname.new(expected_path).cleanpath.to_path
          end
        end

        sig { params(build_file: Dependabot::DependencyFile).returns(String) }
        def wrapper_root_for(build_file)
          path = file_path(build_file)
          root = if target_file?(build_file)
                   File.dirname(path, 3)
                 else
                   File.dirname(path)
                 end

          root == "." ? "" : root
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def file_path(file)
          Pathname.new(file.name).cleanpath.to_path
        end

        # Builds the command for the first wrapper attempt.
        #
        # When the project ships a `gradlew` script we run it: it downloads and executes the Gradle
        # version pinned in the current gradle-wrapper.properties, so wrapper flags are gated on that
        # distributionUrl version. When `gradlew` is missing we instead invoke system Gradle directly,
        # so flags must be gated on the system Gradle's detected version (not the wrapper's) to avoid
        # forwarding options that an older system Gradle does not understand and aborting the run.
        sig do
          params(
            has_local_script: T::Boolean,
            requirements: T::Array[Dependabot::DependencyRequirement],
            original_document: T.nilable(Wrapper::PropertiesDocument),
            cwd: String,
            env: T::Hash[String, String]
          ).returns(String)
        end
        def local_wrapper_command(has_local_script, requirements, original_document, cwd, env)
          return system_wrapper_command(requirements, original_document, cwd, env) unless has_local_script

          distribution_url = original_document&.value_for("distributionUrl")
          gradle_version = Wrapper::ExecutingVersionDetector.from_distribution_url(distribution_url)
          Shellwords.join(["./gradlew"] + build_command_parts(requirements, original_document, gradle_version))
        end

        # Builds the system-Gradle fallback command, gating wrapper flags on the system Gradle's own
        # version (which may differ from the project's wrapper version).
        sig do
          params(
            requirements: T::Array[Dependabot::DependencyRequirement],
            original_document: T.nilable(Wrapper::PropertiesDocument),
            cwd: String,
            env: T::Hash[String, String]
          ).returns(String)
        end
        def system_wrapper_command(requirements, original_document, cwd, env)
          gradle_version = detect_system_gradle_version(cwd, env)
          Shellwords.join(["gradle"] + build_command_parts(requirements, original_document, gradle_version))
        end

        sig do
          params(
            requirements: T::Array[Dependabot::DependencyRequirement],
            original_document: T.nilable(Wrapper::PropertiesDocument),
            gradle_version: T.nilable(Dependabot::Gradle::Version)
          ).returns(T::Array[String])
        end
        def build_command_parts(requirements, original_document, gradle_version)
          wrapper_args = Wrapper::CommandBuilder.new(
            requirements: requirements,
            original_properties: original_document,
            gradle_version: gradle_version
          ).build
          %w(--no-daemon --stacktrace) + wrapper_args
        end

        sig { params(cwd: String, env: T::Hash[String, String]).returns(T.nilable(Dependabot::Gradle::Version)) }
        def detect_system_gradle_version(cwd, env)
          output = SharedHelpers.run_shell_command("gradle --version", cwd: cwd, env: env)
          Wrapper::ExecutingVersionDetector.from_version_output(output)
        rescue SharedHelpers::HelperSubprocessFailed => e
          Dependabot.logger.warn("Unable to detect system Gradle version: #{e.message}")
          nil
        end

        # Gradle builds can be complex, to maximize the chances of a successful we just keep related wrapper files
        # and produce a minimal build for it to run (losing any customisations of the `wrapper` task in the process)
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def files_to_populate
          @dependency_files.filter_map do |f|
            next f if target_file?(f)
            next Dependabot::DependencyFile.new(directory: f.directory, name: f.name, content: "") if build_file?(f)
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def build_file?(file)
          @build_files.include?(File.basename(file.name))
        end

        sig { params(build_file: Dependabot::DependencyFile).returns(String) }
        def base_path(build_file)
          File.dirname(File.join(build_file.directory, build_file.name)).delete_suffix("/gradle/wrapper")
        end

        sig do
          params(
            temp_dir: T.any(Pathname, String),
            local_files: T::Array[Dependabot::DependencyFile],
            updated_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def update_files_content(temp_dir, local_files, updated_files)
          local_files.each do |file|
            f_content = if file.binary?
                          File.binread(File.join(temp_dir, file.directory, file.name))
                        else
                          File.read(File.join(temp_dir, file.directory, file.name))
                        end
            tmp_file = file.dup
            tmp_file.content = tmp_file.binary? ? Base64.encode64(f_content) : f_content
            updated_files[T.must(updated_files.index(file))] = tmp_file
          end
        end

        sig { params(temp_dir: T.any(Pathname, String)).void }
        def populate_temp_directory(temp_dir)
          files_to_populate.each do |file|
            in_path_name = File.join(temp_dir, file.directory, file.name)
            FileUtils.mkdir_p(File.dirname(in_path_name))
            File.binwrite(in_path_name, file.decoded_content)
          end
        end

        sig { params(path: T.any(Pathname, String)).returns(T.nilable(String)) }
        def read_file(path)
          return nil unless File.exist?(path)

          File.read(path)
        end

        # Reconciles the wrapper-regenerated properties file back onto the user's original content,
        # overwriting only the keys that legitimately change for a version bump. Preserves comments,
        # ordering, custom keys and all other user-customized values.
        sig { params(properties_file: T.any(Pathname, String), original_content: T.nilable(String)).void }
        def reconcile_properties(properties_file, original_content)
          regenerated_content = read_file(properties_file)
          reconciled = Wrapper::PropertiesReconciler.reconcile(
            original_content: original_content,
            regenerated_content: regenerated_content
          )
          File.write(properties_file, reconciled) if reconciled && reconciled != regenerated_content
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { returns(T::Array[String]) }
        def proxy_args
          http_proxy = ENV.fetch("HTTP_PROXY", nil)
          https_proxy = ENV.fetch("HTTPS_PROXY", nil)
          http_split = http_proxy&.split(":")
          https_split = https_proxy&.split(":")
          http_proxy_host = http_split&.fetch(1, nil)&.gsub("//", "") || "host.docker.internal"
          https_proxy_host = https_split&.fetch(1, nil)&.gsub("//", "") || "host.docker.internal"
          http_proxy_port = http_split&.fetch(2) || "1080"
          https_proxy_port = https_split&.fetch(2) || "1080"

          args = []
          args += %W(-Dhttp.proxyHost=#{http_proxy_host}) if http_proxy_host
          args += %W(-Dhttp.proxyPort=#{http_proxy_port}) if http_proxy_port
          args += %W(-Dhttps.proxyHost=#{https_proxy_host}) if https_proxy_host
          args += %W(-Dhttps.proxyPort=#{https_proxy_port}) if https_proxy_port
          args
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
      end
    end
  end
end
