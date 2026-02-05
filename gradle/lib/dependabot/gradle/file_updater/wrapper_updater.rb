# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "shellwords"

require "dependabot/gradle/distributions"

module Dependabot
  module Gradle
    class FileUpdater
      class WrapperUpdater
        extend T::Sig
        include Dependabot::Gradle::Distributions

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
        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(build_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::DependencyFile]) }
        def update_files(build_file)
          # We only run this updater if it's a distribution dependency
          return [] unless Distributions.distribution_requirements?(dependency.requirements)

          local_files = dependency_files.select do |file|
            file.directory == build_file.directory && target_file?(file)
          end

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
              validate_distribution, network_timeout = read_wrapper_options(properties_file)
              env = { "JAVA_OPTS" => proxy_args.join(" ") } # set proxy for gradle execution

              command_parts = %w(--no-daemon --stacktrace) + command_args(target_requirements, network_timeout)

              # There is no guarantee that the `gradlew` script is present on the project,
              # if it's not, we fall back to system Gradle
              command = Shellwords.join([has_local_script ? "./gradlew" : "gradle"] + command_parts)

              begin
                # first attempt: run the wrapper task via the local Gradle wrapper (if present)
                # `gradle-wrapper.jar` might not be compatible with the host's Java version or
                # the `gradlew` script may be corrupted, so we try and fall back to system Gradle before giving up
                SharedHelpers.run_shell_command(command, cwd: cwd, env: env)
              rescue SharedHelpers::HelperSubprocessFailed => e
                raise e unless has_local_script # already field with system one, there is no point to retry

                Dependabot.logger.warn("Running #{command} failed, retrying first with system Gradle: #{e.message}")

                # second attempt: run the wrapper task via system gradle and then retry via local wrapper
                system_command = Shellwords.join(["gradle"] + command_parts)
                SharedHelpers.run_shell_command(system_command, cwd: cwd, env: env) # run via system gradle
                SharedHelpers.run_shell_command(command, cwd: cwd, env: env) # retry via local wrapper
              end

              # Restore previous validateDistributionUrl option if it existed
              override_validate_distribution_url_option(properties_file, validate_distribution)

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
        # rubocop:enable Metrics/PerceivedComplexity

        private

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def target_file?(file)
          @target_files.any? { |r| "/#{file.name}".end_with?(r) }
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(requirements: T::Array[T::Hash[Symbol, T.untyped]], network_timeout: T.nilable(String)).returns(T::Array[String]) }
        def command_args(requirements, network_timeout)
          version = T.let(requirements[0]&.[](:requirement), String)
          checksum = T.let(requirements[1]&.[](:requirement), String) if dependency.requirements.size > 1
          distribution_url = T.let(requirements[0]&.[](:source), T::Hash[Symbol, String])[:url]
          distribution_type = distribution_url&.match(/\b(bin|all)\b/)&.captures&.first

          args = %W(wrapper --gradle-version #{version})

          # Executing the wrapper task with `validateDistributionUrl=true`,
          # issues a HEAD request to ensure that the file exists and is reachable.
          # Example: HEAD https://services.gradle.org/distributions/gradle-9.3.0-bin.zip
          # Unfortunately, Dependabot's proxy does not seem to support something about this request
          # This causes the validation to fail and the wrapper task to error out
          # To work around this, we pass `--no-validate-url` to skip the url validation step,
          # Note: this temporarily sets `validateDistributionUrl=false` in `gradle-wrapper.properties`.
          # After the wrapper task completes, we restore the original value, since `--no-validate-url` would otherwise
          # persist the change in the properties file, which is not the behavior we want for users.
          # TODO: Investigate and fix the root cause of the proxy issue and remove this workaround
          # See https://github.com/dependabot/dependabot-core/issues/14036
          args += %w(--no-validate-url)

          # Gradle builds can be very complex, and our current Gradle parsing is limited.
          # To keep `./gradlew wrapper` running reliably, we generate a minimal build that omits the
          # project’s build scripts and customizations. As a result, any `tasks.wrapper {}` DSL configuration
          # defined in the original project is not applied.
          #
          # This approach, combined with https://github.com/gradle/gradle/issues/36172 where the wrapper task
          # relies on hardcoded defaults instead of reading from `gradle-wrapper.properties`, causes
          # `networkTimeout` customizations to be reset to the default value on every Dependabot pull request.
          #
          # This change mitigates the issue by reading the existing value and passing it explicitly to the
          # `wrapper` command, ensuring any custom `networkTimeout` setting is preserved.
          #
          # In future iterations, we may consider parsing the full Gradle build and extracting only the
          # wrapper-related customizations so the project-specific `tasks.wrapper {}` behavior is retained.
          # Alternatively, if Gradle addresses the upstream issue, we can revert to using the default minimal
          # build without needing explicit configuration.
          args += %W(--network-timeout #{network_timeout}) if network_timeout

          args += %W(--distribution-type #{distribution_type}) if distribution_type
          args += %W(--gradle-distribution-sha256-sum #{checksum}) if checksum
          args
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
            f_content = File.read(File.join(temp_dir, file.directory, file.name))
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
            File.write(in_path_name, file.content)
          end
        end

        sig { params(properties_file: T.any(Pathname, String)).returns(T::Array[T.nilable(String)]) }
        def read_wrapper_options(properties_file)
          return [nil, nil] unless File.exist?(properties_file)

          properties_content = File.read(properties_file)
          validate_distribution = properties_content.match(/^validateDistributionUrl=(.*)$/)&.captures&.first
          network_timeout = properties_content.match(/^networkTimeout=(.*)$/)&.captures&.first

          [validate_distribution, network_timeout]
        end

        sig { params(properties_file: T.any(Pathname, String), value: T.nilable(String)).void }
        def override_validate_distribution_url_option(properties_file, value)
          return unless File.exist?(properties_file)

          properties_content = File.read(properties_file)
          updated_content = properties_content.gsub(
            /^validateDistributionUrl=(.*)\n/,
            value ? "validateDistributionUrl=#{value}\n" : ""
          )
          File.write(properties_file, updated_content)
        end

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
