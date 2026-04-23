# typed: strict
# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/registry_client"
require "dependabot/shared_helpers"
require "dependabot/dependency_file"
require "dependabot/maven/distributions"
require "dependabot/maven/file_parser/wrapper_mojo"
require "dependabot/maven/file_updater"
require "dependabot/maven/native_helpers"

module Dependabot
  module Maven
    class FileUpdater
      class WrapperUpdater
        extend T::Sig

        WRAPPER_PROPERTIES_RELATIVE = ".mvn/wrapper/maven-wrapper.properties"
        JAR_RELATIVE                = ".mvn/wrapper/maven-wrapper.jar"
        DOWNLOADER_RELATIVE         = ".mvn/wrapper/MavenWrapperDownloader.java"

        # Named constants for all wrapper scripts, split by platform.
        #
        # Every Unix shell script must have
        # Mode::EXECUTABLE set after the update
        # Windows executables can skip that as it carries no meaning
        UNIX_SCRIPTS    = %w(mvnw mvnwDebug).freeze
        WINDOWS_SCRIPTS = %w(mvnw.cmd mvnwDebug.cmd).freeze
        ALL_SCRIPTS = T.let((UNIX_SCRIPTS + WINDOWS_SCRIPTS).freeze, T::Array[String])

        sig do
          params(
            dependency_files: T::Array[DependencyFile],
            dependency: Dependency,
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency_files:, dependency:, credentials:)
          @dependency_files = dependency_files
          @dependency       = dependency
          @credentials      = credentials
        end

        # Entry point. Updates the wrapper properties file in-place, then
        # regenerates shell scripts via the native wrapper:wrapper goal.
        # Returns an empty array for non-wrapper dependencies.
        sig { params(buildfile: DependencyFile).returns(T::Array[DependencyFile]) }
        def update_files(buildfile)
          # Return immediately for any non-wrapper dependency.
          return [] unless Distributions.distribution_requirements?(dependency.requirements)
          return [] unless wrapper_properties_file

          SharedHelpers.in_a_temporary_directory(project_root(buildfile)) do
            write_dependency_files

            # Drop both SHA-256 checksum properties before invoking the native command.
            # If they remain, Maven verifies the old checksum against the new version and fails.
            # The checksums cannot be passed in during generation because the wrapper does not support it.
            # As a workaround, we recompute and re-add them once the generation completes
            strip_checksum_properties

            distribution_type = distribution_type_from_requirements
            # Run the native wrapper command to regenerate the shell scripts
            run_wrapper_command(distribution_type)

            # Maven Central only publishes SHA-512 checksums.
            # But the wrapper only supports SHA-256 validation
            # We need compute the SHA-256 digest directly from the artifact
            # and write it into the regenerated properties file.
            update_checksum_properties

            collect_updated_files(distribution_type)
          end
        end

        private

        sig { returns(Dependency) }
        attr_reader :dependency

        # Removes distributionSha256Sum and wrapperSha256Sum from the on-disk
        # properties file so that the wrapper:wrapper command can download the
        # new artifact without Maven aborting on a stale checksum mismatch.
        sig { void }
        def strip_checksum_properties
          return unless File.exist?(WRAPPER_PROPERTIES_RELATIVE)

          content = File.read(WRAPPER_PROPERTIES_RELATIVE)
          stripped = content.lines.reject { |l| l.match?(/\A(?:distribution|wrapper)Sha256Sum\s*=/) }.join
          File.write(WRAPPER_PROPERTIES_RELATIVE, stripped)
        end

        # Computes a fresh digest from the updated artifact
        # This is needed because Maven Central only publishes SHA-512 checksums,
        # while the wrapper only supports validations for the SHA-256
        #
        # Raises if an expected artifact cannot be found in the cache, because
        # a stale or missing checksum would silently weaken integrity checking.
        sig { returns(T.nilable(Integer)) }
        def update_checksum_properties
          dist_req = dependency.requirements.find { |r| r[:source][:property] == "distributionUrl" }
          wrapper_req = dependency.requirements.find { |r| r[:source][:property] == "wrapperUrl" }

          dist_checksum = dist_req&.dig(:metadata, :distribution_sha256_sum)
          wrapper_checksum = wrapper_req&.dig(:metadata, :wrapper_sha256_sum)

          Dependabot.logger.debug "updating checksum properties " \
                                  "dist=#{!dist_checksum.nil?} wrap=#{!wrapper_checksum.nil?}"
          return unless dist_checksum || wrapper_checksum
          return unless File.exist?(WRAPPER_PROPERTIES_RELATIVE)

          content = File.read(WRAPPER_PROPERTIES_RELATIVE)

          if dist_checksum
            dist_url = dist_req.dig(:source, :url)
            content = set_checksum_from_url(
              content,
              "distributionSha256Sum",
              T.cast(dist_url, String)
            )
          end
          if wrapper_checksum
            wrapper_url = wrapper_req.dig(:source, :url)
            content = set_checksum_from_url(
              content,
              "wrapperSha256Sum",
              T.cast(wrapper_url, String)
            )
          end
          File.write(WRAPPER_PROPERTIES_RELATIVE, content)
        end

        sig { params(content: String, property_name: String, url: String).returns(String) }
        def set_checksum_from_url(content, property_name, url)
          sha256 = calculate_sha256_from_url(url)
          set_checksum_property(content, property_name, sha256)
        end

        sig { params(url: String).returns(String) }
        def calculate_sha256_from_url(url)
          @sha256_cache = T.let(@sha256_cache, T.nilable(T::Hash[String, String]))
          @sha256_cache ||= {}
          if @sha256_cache.key?(url)
            Dependabot.logger.debug "SHA-256 cache hit for #{url}"
            return T.must(@sha256_cache[url])
          end

          Dependabot.logger.info "Downloading Maven distribution: #{url} to calculate the sha256 checksum"
          response = Dependabot::RegistryClient.get(url: url, headers: auth_headers_for_url(url))
          raise_on_auth_failure(url, response)

          raise "Failed to download #{url}: HTTP #{response.status}" unless response.status == 200

          hash = Digest::SHA256.hexdigest(response.body)
          Dependabot.logger.debug "Computed SHA-256: #{hash}"
          @sha256_cache[url] = hash
        rescue Dependabot::PrivateSourceAuthenticationFailure
          raise
        rescue StandardError => e
          Dependabot.logger.error "Checksum computation failed with an unexpected error: #{e.message}"
          raise
        end

        sig { params(url: String, response: T.untyped).void }
        def raise_on_auth_failure(url, response)
          return unless response.status == 401

          repository_url = url.match(%r{^(https?://[^/]+(?:/[^/]+)*)/org/})&.captures&.first ||
                           URI.parse(url).host.to_s
          raise Dependabot::PrivateSourceAuthenticationFailure, repository_url
        end

        sig { params(url: String).returns(T::Hash[String, String]) }
        def auth_headers_for_url(url)
          Dependabot.logger.debug "Building auth headers for: #{url}"

          cred = maven_registry_credential(url)
          unless cred
            Dependabot.logger.debug "No matching credential found for #{url}, using no auth"
            return {}
          end

          username = cred["username"]
          password = cred["password"]
          unless username
            Dependabot.logger.debug "Credential for #{url} has no username, using no auth"
            return {}
          end

          Dependabot.logger.debug "Using Basic auth for #{url} (username: #{username})"
          { "Authorization" => "Basic #{Base64.strict_encode64("#{username}:#{password}")}" }
        end

        sig { params(content: String, key: String, value: String).returns(String) }
        def set_checksum_property(content, key, value)
          Dependabot.logger.debug "Appending #{key}"
          "#{content.rstrip}\n#{key}=#{value}\n"
        end

        sig { params(distribution_type: String).void }
        def run_wrapper_command(distribution_type)
          distribution_version = distribution_version_from_requirements
          wrapper_version = maven_wrapper_version_from_requirements
          extra_args = build_extra_args_from_requirements
          NativeHelpers.run_mvnw_wrapper(
            version: distribution_version,
            wrapper_plugin_version: wrapper_version,
            env: build_env,
            distribution_type: distribution_type,
            extra_args: extra_args
          )
        end

        sig { returns(String) }
        def maven_wrapper_version_from_requirements
          wrapper_version = dependency.requirements
                                      .find { |r| r.dig(:metadata, :wrapper_version) }
                                      &.dig(:metadata, :wrapper_version)
          raise "Could not determine Maven Wrapper version from dependency requirements" unless wrapper_version

          T.cast(wrapper_version, String)
        end

        sig { returns(String) }
        def distribution_version_from_requirements
          distribution_version = dependency.requirements
                                           .find { |r| r.dig(:metadata, :distribution_version) }
                                           &.dig(:metadata, :distribution_version)
          raise "Could not determine distribution version from dependency requirements" unless distribution_version

          T.cast(distribution_version, String)
        end

        sig { returns(String) }
        def distribution_type_from_requirements
          distribution_type = dependency.requirements
                                        .find { |r| r.dig(:metadata, :distribution_type) }
                                        &.dig(:metadata, :distribution_type)
          raise "Could not determine distribution type from dependency requirements" unless distribution_type

          T.cast(distribution_type, String)
        end

        sig { returns(T::Array[String]) }
        def build_extra_args_from_requirements
          args = T.let([], T::Array[String])
          include_debug = dependency.requirements
                                    .find { |r| r.dig(:metadata, :include_debug_script) }
                                    &.dig(:metadata, :include_debug_script)
          args << "-DincludeDebugScript=true" if include_debug
          args
        end

        # Builds the environment hash passed to the native wrapper command,
        # including proxy, registry URL, and credentials.
        sig { returns(T::Hash[String, String]) }
        def build_env
          env = T.let({}, T::Hash[String, String])
          if (proxy = ENV.fetch("HTTPS_PROXY", nil))
            proxy_url = URI.parse(proxy)
            Dependabot.logger.debug "Using proxy host: #{proxy_url.host}"
            env["PROXY_HOST"] = proxy_url.host.to_s
          end

          registry_base, cred = resolve_registry_base_and_credential
          env.merge!(build_registry_env(registry_base, cred))
          env.merge!(build_credential_env(cred))

          if Dependabot.logger.debug?
            env["MVNW_VERBOSE"] = "true"
            safe_env = env.except("MVNW_PASSWORD")
            safe_env["MVNW_PASSWORD"] = "[REDACTED]" if env.key?("MVNW_PASSWORD")
            Dependabot.logger.debug "build_env result: #{safe_env}"
          end

          env
        end

        sig do
          returns([T.nilable(String), T.nilable(Dependabot::Credential)])
        end
        def resolve_registry_base_and_credential
          dist_req = dependency.requirements.find { |r| r[:source][:property] == "distributionUrl" }
          dist_url = dist_req&.dig(:source, :url)
          Dependabot.logger.debug "Distribution URL from requirements: #{dist_url}"

          registry_base_regex = %r{^(https?://[^/]+(?:/[^/]+)*)/org/apache/maven/apache-maven/}
          registry_base = dist_url&.match(registry_base_regex)&.captures&.first
          Dependabot.logger.debug "Extracted registry base: #{registry_base || '(none)'}"

          cred = maven_registry_credential(registry_base)
          Dependabot.logger.debug "Matched credential: #{cred ? "url=#{cred.fetch('url', '(none)')}" : '(none)'}"

          [registry_base, cred]
        end

        sig do
          params(registry_base: T.nilable(String), cred: T.nilable(Dependabot::Credential))
            .returns(T::Hash[String, String])
        end
        def build_registry_env(registry_base, cred)
          if registry_base
            { "MVNW_REPOURL" => registry_base }
          elsif cred&.fetch("replaces_base", false)
            { "MVNW_REPOURL" => cred.fetch("url").chomp("/") }
          else
            {}
          end
        end

        sig { params(cred: T.nilable(Dependabot::Credential)).returns(T::Hash[String, String]) }
        def build_credential_env(cred)
          return {} unless cred

          env = T.let({}, T::Hash[String, String])
          env["MVNW_USERNAME"] = T.must(cred["username"]) if cred["username"]
          env["MVNW_PASSWORD"] = T.must(cred["password"]) if cred["password"]
          env
        end

        sig { params(registry_base: T.nilable(String)).returns(T.nilable(Dependabot::Credential)) }
        def maven_registry_credential(registry_base)
          maven_creds = @credentials.select { |c| c["type"] == "maven_repository" }

          if registry_base
            url_matches = maven_creds.select do |c|
              cred_url = c.fetch("url", "").chomp("/")
              !cred_url.empty? && registry_base.start_with?(cred_url)
            end
            return url_matches.max_by { |c| c.fetch("url", "").length } if url_matches.any?
          end

          maven_creds.find { |c| c.fetch("replaces_base", false) }
        end

        sig { params(buildfile: DependencyFile).returns(String) }
        def project_root(buildfile)
          File.dirname(buildfile.path)
        end

        # Assembles all updated files: properties, scripts, and the type-specific artifact.
        sig { params(dist_type: String).returns(T::Array[DependencyFile]) }
        def collect_updated_files(dist_type)
          collect_properties_file + collect_script_files + collect_artifact_file(dist_type)
        end

        # Returns a DependencyFile for the updated maven-wrapper.properties, or [] if absent.
        sig { returns(T::Array[DependencyFile]) }
        def collect_properties_file
          return [] unless File.exist?(WRAPPER_PROPERTIES_RELATIVE)

          [DependencyFile.new(
            name: WRAPPER_PROPERTIES_RELATIVE,
            content: File.read(WRAPPER_PROPERTIES_RELATIVE),
            directory: wrapper_properties_file&.directory || "/"
          )]
        end

        # Returns DependencyFiles for all wrapper scripts that exist on disk,
        # marking Unix scripts as executable.
        sig { returns(T::Array[DependencyFile]) }
        def collect_script_files
          ALL_SCRIPTS.filter_map do |script|
            next unless File.exist?(script)

            file = DependencyFile.new(
              name: script,
              content: File.read(script),
              directory: wrapper_properties_file&.directory || "/"
            )
            file.mode = DependencyFile::Mode::EXECUTABLE if UNIX_SCRIPTS.include?(script)
            file
          end
        end

        # Returns the type-specific artifact: the wrapper JAR for "bin"/"script",
        # MavenWrapperDownloader.java for "source", or [] for "only-script".
        sig { params(dist_type: String).returns(T::Array[DependencyFile]) }
        def collect_artifact_file(dist_type)
          case dist_type
          when "bin", "script"
            return [] unless File.exist?(JAR_RELATIVE)

            [DependencyFile.new(
              name: JAR_RELATIVE,
              content: Base64.encode64(File.binread(JAR_RELATIVE)),
              content_encoding: DependencyFile::ContentEncoding::BASE64,
              directory: wrapper_properties_file&.directory || "/"
            )]
          when "source"
            return [] unless File.exist?(DOWNLOADER_RELATIVE)

            [DependencyFile.new(
              name: DOWNLOADER_RELATIVE,
              content: File.read(DOWNLOADER_RELATIVE),
              directory: wrapper_properties_file&.directory || "/"
            )]
          else
            []
          end
        end

        # Memoized lookup of the maven-wrapper.properties DependencyFile.
        sig { returns(T.nilable(DependencyFile)) }
        def wrapper_properties_file
          @wrapper_properties_file ||= T.let(
            @dependency_files.find { |f| f.name.end_with?("maven-wrapper.properties") },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        # Writes all dependency files to the current working directory,
        # base64-decoding binary files (e.g. the wrapper JAR) as needed.
        sig { void }
        def write_dependency_files
          @dependency_files.each do |file|
            FileUtils.mkdir_p(File.dirname(file.name))
            if file.content_encoding == DependencyFile::ContentEncoding::BASE64
              File.binwrite(file.name, Base64.decode64(T.must(file.content)))
            else
              File.write(file.name, file.content)
            end
          end
        end
      end
    end
  end
end
