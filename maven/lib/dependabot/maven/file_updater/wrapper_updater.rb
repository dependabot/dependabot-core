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
            credentials: T::Array[Dependabot::Credential],
            distribution_version: T.nilable(String),
            wrapper_version: T.nilable(String)
          ).void
        end
        def initialize(dependency_files:, dependency:, credentials:, distribution_version: nil, wrapper_version: nil)
          @dependency_files = dependency_files
          @dependency       = dependency
          @credentials      = credentials
          # Optional resolved versions. When a grouped update bumps both the distribution and the
          # wrapper plugin, neither dependency alone carries both new versions, so the caller resolves
          # them and passes them in. When nil we fall back to reading them from the dependency.
          @distribution_version_override = distribution_version
          @wrapper_version_override      = wrapper_version
        end

        # Entry point. Updates the wrapper properties file in-place, then
        # regenerates shell scripts via the native wrapper:wrapper goal.
        # Returns an empty array for non-wrapper dependencies.
        sig { params(buildfile: DependencyFile).returns(T::Array[DependencyFile]) }
        def update_files(buildfile)
          # Return immediately for any non-wrapper dependency.
          return [] unless Distributions.distribution_requirements?(dependency.requirements)
          return [] unless wrapper_properties_file

          # Capture the user's original properties before we mutate the on-disk copy, so we can
          # tell which checksums they were tracking and restore exactly those afterwards.
          original_properties = wrapper_properties_file&.content

          SharedHelpers.in_a_temporary_directory(project_root(buildfile)) do
            write_dependency_files

            # Drop both SHA-256 checksum properties before invoking the native command.
            # If they remain, Maven verifies the old checksum against the new version and fails.
            # We recompute and restore them afterwards: the plugin can accept -DdistributionSha256Sum /
            # -DwrapperSha256Sum, but it does not derive the value for us, and Maven Central only
            # publishes SHA-512, so we must download the artifact and compute the SHA-256 ourselves.
            strip_checksum_properties

            distribution_type = distribution_type_from_requirements
            # Run the native wrapper command to regenerate the shell scripts
            run_wrapper_command(distribution_type)

            # Maven Central only publishes SHA-512 checksums.
            # But the wrapper only supports SHA-256 validation
            # We need compute the SHA-256 digest directly from the artifact
            # and write it into the regenerated properties file.
            restore_checksum_properties(original_properties)

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
          return unless File.exist?(properties_path)

          content = File.read(properties_path)
          stripped = content.lines.reject { |l| l.match?(/\A\s*(?:distribution|wrapper)Sha256Sum\s*[=:]/) }.join
          File.write(properties_path, stripped)
        end

        # Recomputes the SHA-256 checksums the user was already tracking and writes them onto the
        # regenerated properties file. This is needed because Maven Central only publishes SHA-512
        # checksums, while the wrapper only validates SHA-256, so the native command cannot produce
        # them for us.
        #
        # The URLs are read back from the *regenerated* properties file (not the dependency
        # requirements), so this works no matter which coordinate was bumped: a wrapper-plugin bump
        # still restores the distribution checksum, and a distribution bump still restores the wrapper
        # checksum. We only restore checksums the user's original file actually contained, so we never
        # add integrity properties the project did not opt into.
        sig { params(original_properties: T.nilable(String)).void }
        def restore_checksum_properties(original_properties)
          return unless File.exist?(properties_path)
          return if original_properties.nil?

          had_dist_checksum = property_present?(original_properties, "distributionSha256Sum")
          had_wrapper_checksum = property_present?(original_properties, "wrapperSha256Sum")

          Dependabot.logger.debug "restoring checksum properties " \
                                  "dist=#{had_dist_checksum} wrap=#{had_wrapper_checksum}"
          return unless had_dist_checksum || had_wrapper_checksum

          content = File.read(properties_path)

          if had_dist_checksum && (dist_url = FileParser::WrapperMojo.get_property_value(content, "distributionUrl"))
            content = set_checksum_from_url(content, "distributionSha256Sum", dist_url)
          end
          if had_wrapper_checksum && (wrapper_url = FileParser::WrapperMojo.get_property_value(content, "wrapperUrl"))
            content = set_checksum_from_url(content, "wrapperSha256Sum", wrapper_url)
          end
          File.write(properties_path, content)
        end

        sig { params(content: String, key: String).returns(T::Boolean) }
        def property_present?(content, key)
          !FileParser::WrapperMojo.get_property_value(content, key).nil?
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
          # Registry auth is injected by Dependabot's proxy (which matches on host + path prefix),
          # so we deliberately send no auth headers here — core never receives usable credentials.
          response = Dependabot::RegistryClient.get(url: url)
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

        sig { params(content: String, key: String, value: String).returns(String) }
        def set_checksum_property(content, key, value)
          pattern = /^[ \t]*#{Regexp.escape(key)}[ \t]*[=:].*$/
          if content.match?(pattern)
            Dependabot.logger.debug "Replacing #{key}"
            content.sub(pattern, "#{key}=#{value}")
          else
            Dependabot.logger.debug "Appending #{key}"
            "#{content.rstrip}\n#{key}=#{value}\n"
          end
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
            extra_args: extra_args,
            cwd: wrapper_dir
          )
        end

        sig { returns(String) }
        def maven_wrapper_version_from_requirements
          return T.must(@wrapper_version_override) if @wrapper_version_override

          wrapper_version = dependency.requirements
                                      .find { |r| r.dig(:metadata, :wrapper_version) }
                                      &.dig(:metadata, :wrapper_version)
          raise "Could not determine Maven Wrapper version from dependency requirements" unless wrapper_version

          T.cast(wrapper_version, String)
        end

        sig { returns(String) }
        def distribution_version_from_requirements
          return T.must(@distribution_version_override) if @distribution_version_override

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
          # The plugin exposes this via the `includeDebug` user property (the field is named
          # includeDebugScript internally). Passing -DincludeDebugScript is silently ignored, which
          # would drop the user's mvnwDebug scripts on every update.
          # https://maven.apache.org/tools/wrapper/maven-wrapper-plugin/wrapper-mojo.html
          args << "-DincludeDebug=true" if include_debug
          args
        end

        # Builds the environment hash passed to the native wrapper command.
        # Sets the proxy host and, for a private/mirror registry, MVNW_REPOURL. Registry auth is
        # injected by Dependabot's proxy, so no username/password is set here (core never receives them).
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

          if Dependabot.logger.debug?
            env["MVNW_VERBOSE"] = "true"
            Dependabot.logger.debug "build_env result: #{env}"
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
          elsif cred&.replaces_base?
            { "MVNW_REPOURL" => cred.fetch("url").chomp("/") }
          else
            {}
          end
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

          maven_creds.find(&:replaces_base?)
        end

        sig { params(buildfile: DependencyFile).returns(String) }
        def project_root(buildfile)
          # Always materialise the repo relative to its root; per-wrapper working directories are
          # handled via `wrapper_dir` (the mvn command runs there and files are read/written there).
          buildfile.directory
        end

        # Directory that contains this wrapper (the folder holding `.mvn/wrapper`), relative to the
        # repo root. "." for a root wrapper, e.g. "submodule" for a module wrapper. Derived from the
        # properties file so multi-module repos update the correct wrapper in place.
        sig { returns(String) }
        def wrapper_dir
          @wrapper_dir ||= T.let(
            begin
              name = wrapper_properties_file&.name.to_s
              dir = name.sub(%r{/?#{Regexp.escape(WRAPPER_PROPERTIES_RELATIVE)}\z}, "")
              dir.empty? ? "." : dir
            end,
            T.nilable(String)
          )
        end

        sig { params(path: String).returns(String) }
        def in_wrapper_dir(path)
          wrapper_dir == "." ? path : File.join(wrapper_dir, path)
        end

        sig { returns(String) }
        def properties_path
          in_wrapper_dir(WRAPPER_PROPERTIES_RELATIVE)
        end

        sig { returns(String) }
        def jar_path
          in_wrapper_dir(JAR_RELATIVE)
        end

        sig { returns(String) }
        def downloader_path
          in_wrapper_dir(DOWNLOADER_RELATIVE)
        end

        # Assembles all updated files: properties, scripts, and the type-specific artifact.
        sig { params(dist_type: String).returns(T::Array[DependencyFile]) }
        def collect_updated_files(dist_type)
          collect_properties_file + collect_script_files + collect_artifact_file(dist_type)
        end

        # Returns a DependencyFile for the updated maven-wrapper.properties, or [] if absent.
        sig { returns(T::Array[DependencyFile]) }
        def collect_properties_file
          return [] unless File.exist?(properties_path)

          [DependencyFile.new(
            name: properties_path,
            content: File.read(properties_path),
            directory: wrapper_properties_file&.directory || "/"
          )]
        end

        # Returns DependencyFiles for all wrapper scripts that exist on disk,
        # marking Unix scripts as executable.
        sig { returns(T::Array[DependencyFile]) }
        def collect_script_files
          ALL_SCRIPTS.filter_map do |script|
            script_file = in_wrapper_dir(script)
            next unless File.exist?(script_file)

            file = DependencyFile.new(
              name: script_file,
              content: File.read(script_file),
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
            return [] unless File.exist?(jar_path)

            [DependencyFile.new(
              name: jar_path,
              content: Base64.encode64(File.binread(jar_path)),
              content_encoding: DependencyFile::ContentEncoding::BASE64,
              directory: wrapper_properties_file&.directory || "/"
            )]
          when "source"
            return [] unless File.exist?(downloader_path)

            [DependencyFile.new(
              name: downloader_path,
              content: File.read(downloader_path),
              directory: wrapper_properties_file&.directory || "/"
            )]
          else
            []
          end
        end

        # Memoized lookup of the maven-wrapper.properties DependencyFile for THIS wrapper. Prefers the
        # file referenced by the dependency's requirements so multi-module repos pick the right one.
        sig { returns(T.nilable(DependencyFile)) }
        def wrapper_properties_file
          @wrapper_properties_file ||= T.let(
            begin
              req_file = dependency.requirements
                                   .find { |r| r.dig(:source, :type) == Distributions::DISTRIBUTION_DEPENDENCY_TYPE }
                                   &.fetch(:file, nil)
              @dependency_files.find { |f| f.name == req_file } ||
                @dependency_files.find { |f| f.name.end_with?("maven-wrapper.properties") }
            end,
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
