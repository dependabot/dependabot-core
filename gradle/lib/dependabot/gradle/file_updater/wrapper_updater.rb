# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "shellwords"
require "set"

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
            command_parts = %w(--no-daemon --stacktrace) + command_args(target_requirements)
            command = Shellwords.join([has_local_script ? "./gradlew" : "gradle"] + command_parts)

            Dir.chdir(cwd) do
              FileUtils.chmod("+x", "./gradlew") if has_local_script

              properties_file = File.join(cwd, "gradle/wrapper/gradle-wrapper.properties")
              # Preserve all custom properties before running the wrapper command
              original_properties = get_properties(properties_file)
              env = { "JAVA_OPTS" => proxy_args.join(" ") } # set proxy for gradle execution

              begin
                # first attempt: run the wrapper task via the local gradle wrapper (if present)
                # `gradle-wrapper.jar` might be too old to run on host's Java version
                SharedHelpers.run_shell_command(command, cwd: cwd, env: env)
              rescue SharedHelpers::HelperSubprocessFailed => e
                raise e unless has_local_script # already field with system one, there is no point to retry

                Dependabot.logger.warn("Running #{command} failed, retrying first with system Gradle: #{e.message}")

                # second attempt: run the wrapper task via system gradle and then retry via local wrapper
                system_command = Shellwords.join(["gradle"] + command_parts)
                SharedHelpers.run_shell_command(system_command, cwd: cwd, env: env) # run via system gradle
                SharedHelpers.run_shell_command(command, cwd: cwd, env: env) # retry via local wrapper
              end

              # Restore custom properties that should be preserved
              restore_properties(properties_file, original_properties)

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

        sig { params(requirements: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[String]) }
        def command_args(requirements)
          version = T.let(requirements[0]&.[](:requirement), String)
          checksum = T.let(requirements[1]&.[](:requirement), String) if dependency.requirements.size > 1
          distribution_url = T.let(requirements[0]&.[](:source), T::Hash[Symbol, String])[:url]
          distribution_type = distribution_url&.match(/\b(bin|all)\b/)&.captures&.first

          # --no-validate-url is required to bypass HTTP proxy issues when running ./gradlew
          # This prevents validation failures during the wrapper update process
          # Note: This temporarily sets validateDistributionUrl=false in gradle-wrapper.properties
          # The original value (along with all other custom properties) is restored after the wrapper task completes
          # see methods `get_properties` and `restore_properties` for more details
          args = %W(wrapper --gradle-version #{version} --no-validate-url)
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

        # Reads all properties from the gradle-wrapper.properties file
        # Returns a hash of property key-value pairs
        sig { params(properties_file: T.any(Pathname, String)).returns(T::Hash[String, String]) }
        def get_properties(properties_file)
          return {} unless File.exist?(properties_file)

          properties_content = File.read(properties_file)
          properties = {}

          properties_content.each_line do |line|
            # Skip comments and empty lines
            next if line.strip.start_with?("#") || line.strip.empty?

            # Parse property lines in the format: key=value
            if line =~ /^([^=]+)=(.*)$/
              key = ::Regexp.last_match(1).strip
              value = ::Regexp.last_match(2).strip
              properties[key] = value
            end
          end

          properties
        end

        # Restores custom properties after running the gradle wrapper command
        # The wrapper command regenerates gradle-wrapper.properties with default values
        # This method restores user customizations while keeping the updated distribution settings
        sig { params(properties_file: T.any(Pathname, String), original_properties: T::Hash[String, String]).void }
        def restore_properties(properties_file, original_properties)
          return unless File.exist?(properties_file)
          return if original_properties.empty?

          # Properties that are intentionally updated by the wrapper command and should NOT be restored
          updated_properties = %w[
            distributionUrl
            distributionSha256Sum
          ]

          # Read the newly generated properties file
          new_content = File.read(properties_file)
          new_properties = {}

          new_content.each_line do |line|
            next if line.strip.start_with?("#") || line.strip.empty?

            if line =~ /^([^=]+)=(.*)$/
              key = ::Regexp.last_match(1).strip
              new_properties[key] = line
            end
          end

          # Restore original values for properties that weren't intentionally updated
          result_lines = []
          added_keys = Set.new

          # First, add all properties from the new file, replacing with original values where appropriate
          new_content.each_line do |line|
            if line.strip.start_with?("#") || line.strip.empty?
              result_lines << line
              next
            end

            if line =~ /^([^=]+)=/
              key = ::Regexp.last_match(1).strip
              added_keys.add(key)

              # Use original value if this property should be preserved
              if !updated_properties.include?(key) && original_properties.key?(key)
                result_lines << "#{key}=#{original_properties[key]}\n"
              else
                result_lines << line
              end
            else
              result_lines << line
            end
          end

          # Add any properties from the original file that weren't in the new file
          original_properties.each do |key, value|
            next if added_keys.include?(key)
            next if updated_properties.include?(key)

            result_lines << "#{key}=#{value}\n"
          end

          File.write(properties_file, result_lines.join)
        end

        # Legacy method for backward compatibility - now uses get_properties
        # @deprecated Use get_properties instead
        sig { params(properties_file: T.any(Pathname, String)).returns(T.nilable(String)) }
        def get_validate_distribution_url_option(properties_file)
          properties = get_properties(properties_file)
          properties["validateDistributionUrl"]
        end

        # Legacy method for backward compatibility - now uses restore_properties
        # @deprecated This method is no longer used, restore_properties handles this
        sig { params(properties_file: T.any(Pathname, String), value: T.nilable(String)).void }
        def override_validate_distribution_url_option(properties_file, value)
          # This method is now a no-op, as restore_properties handles all property restoration
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
