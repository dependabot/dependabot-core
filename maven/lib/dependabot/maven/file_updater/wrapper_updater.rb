# typed: strict
# frozen_string_literal: true

require "base64"
require "fileutils"
require "sorbet-runtime"

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
        ALL_SCRIPTS     = T.let((UNIX_SCRIPTS + WINDOWS_SCRIPTS).freeze, T::Array[String])

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

          if mvnd_distribution?
            Dependabot.logger.warn("Maven daemon (mvnd) distribution is not supported, skipping wrapper update")
            return []
          end

          if takari_distribution?
            Dependabot.logger.warn("Takari distribution is not supported, skipping wrapper update")
            return []
          end

          props = FileParser::WrapperMojo.load_properties(
            T.must(T.must(wrapper_properties_file).content)
          )

          SharedHelpers.in_a_temporary_directory(project_root(buildfile)) do
            write_dependency_files

            # Replace the property file.
            update_properties_file_directly

            # Run the native wrapper command to regenerate shell scripts.
            run_wrapper_command(props)
            collect_updated_files(props.distribution_type)
          end
        end

        private

        sig { returns(Dependency) }
        attr_reader :dependency

        # Rewrites maven-wrapper.properties by substituting each
        # requirement's old replace_string with the new one, preserving all
        # other content (registry hostname, escaping, comments, etc.).
        sig { void }
        def update_properties_file_directly
          return unless wrapper_properties_file

          old_content = T.must(T.must(wrapper_properties_file).content)
          new_content = old_content.dup

          dependency.requirements.zip(T.must(dependency.previous_requirements)).each do |new_req, old_req|
            next unless new_req.dig(:source, :type) == Distributions::DISTRIBUTION_DEPENDENCY_TYPE

            old_replace = old_req&.dig(:source, :replace_string)
            new_replace = build_replace_string(new_req, old_req)
            next unless old_replace && new_replace

            new_content = new_content.gsub(old_replace, new_replace)
          end

          File.write(WRAPPER_PROPERTIES_RELATIVE, new_content)
        end

        sig do
          params(
            new_req: T::Hash[Symbol, T.untyped],
            old_req: T.nilable(T::Hash[Symbol, T.untyped])
          ).returns(T.nilable(String))
        end
        def build_replace_string(new_req, old_req)
          old_replace = old_req&.dig(:source, :replace_string)
          return nil unless old_replace

          case new_req.dig(:source, :property)
          when "distributionUrl", "wrapperUrl"
            # Swap only the version segment inside the full URL, preserving the
            # registry hostname, path, and any Java-Properties \: escaping verbatim.
            # e.g. "https\://.../apache-maven-3.9.8-bin.zip" → "...3.9.9..."
            old_version = old_req.fetch(:requirement, nil)
            new_version = new_req.fetch(:requirement)
            old_replace.gsub(old_version, new_version) if old_version
          when "wrapperVersion"
            # Bare version value, e.g. "3.3.4" — replace with the new version directly.
            new_req.fetch(:requirement)
          when "scriptVersion"
            # Version lives only in the mvnw script comment (MWRAPPER-120/134 gap in 3.3.0);
            # nothing to substitute in the properties file — let wrapper:wrapper handle it.
            nil
          end
        end

        sig { params(props: FileParser::WrapperMojo::WrapperProperties).void }
        def run_wrapper_command(props)
          NativeHelpers.run_mvnw_wrapper(
            version: maven_distribution_version,
            wrapper_plugin_version: props.wrapper_version ||
                                    T.must(NativeHelpers::WRAPPER_PLUGIN_DEFAULT_VERSION),
            dir: Dir.pwd,
            env: build_env,
            extra_args: FileParser::WrapperMojo.read_wrapper_options(Dir.pwd)
          )
        end

        # Builds the environment hash passed to the native wrapper command,
        # including proxy, registry URL, and credentials.
        sig { returns(T::Hash[String, String]) }
        def build_env
          proxy_url = URI.parse(ENV.fetch("HTTPS_PROXY"))
          env = { "PROXY_HOST" => proxy_url.host.to_s }

          dist_url = distribution_url_from_requirement
          registry_base_regex = %r{^(https?://[^/]+(?:/[^/]+)*)/org/apache/maven/apache-maven/}
          registry_base = dist_url&.then { |u| u.match(registry_base_regex)&.captures&.first }
          cred = maven_registry_credential(registry_base)

          env.merge!(build_registry_env(registry_base, cred))
          env.merge!(build_credential_env(cred))

          if Dependabot.logger.debug?
            env["MVNW_VERBOSE"] = "true"
            Dependabot.logger.debug("WrapperUpdater build_env: #{env}")
          end

          env
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

        sig { returns(T.nilable(String)) }
        def distribution_url_from_requirement
          req = dependency.requirements.find do |r|
            r.dig(:source, :property) == "distributionUrl"
          end
          req&.dig(:source, :url)
        end

        # Returns true when the distributionUrl points to a Maven daemon (mvnd) archive.
        # mvnd uses a separate distribution mechanism and is not supported.
        sig { returns(T::Boolean) }
        def mvnd_distribution?
          url = distribution_url_from_requirement
          url&.include?("mvnd") == true
        end

        # Returns true when the distributionUrl points to a Takari distribution.
        # Takari is the legacy version of the maven wrapper that is no longer supported
        #
        sig { returns(T::Boolean) }
        def takari_distribution?
          url = distribution_url_from_requirement
          url&.include?("takari") == true
        end

        # Returns the new Apache Maven version from the distributionUrl requirement.
        sig { returns(String) }
        def maven_distribution_version
          req = dependency.requirements.find do |r|
            r.dig(:source, :property) == "distributionUrl"
          end
          T.must(req).fetch(:requirement)
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
            @dependency_files.find do |f|
              f.name.end_with?("maven-wrapper.properties")
            end,
            T.nilable(Dependabot::DependencyFile)
          )
        end

        # Writes all dependency files to the current working directory,
        # base64-decoding binary files (e.g. the wrapper JAR) as needed.
        sig { void }
        def write_dependency_files
          @dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(File.dirname(path))
            if file.content_encoding == DependencyFile::ContentEncoding::BASE64
              File.binwrite(path, Base64.decode64(T.must(file.content)))
            else
              File.write(path, file.content)
            end
          end
        end
      end
    end
  end
end
