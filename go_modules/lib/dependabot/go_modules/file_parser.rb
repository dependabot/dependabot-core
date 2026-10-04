# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "open3"
require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/go_modules/go_work_parser"
require "dependabot/go_modules/go_mod_manifest"
require "dependabot/go_modules/path_converter"
require "dependabot/go_modules/replace_stubber"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/go_modules/version"
require "dependabot/go_modules/language"
require "dependabot/go_modules/package_manager"

module Dependabot
  module GoModules
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      # NOTE: repo_contents_path is typed as T.nilable(String) to maintain
      # compatibility with the base FileParser class signature. However,
      # we validate it's not nil at runtime since it's always required in production.
      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          source: T.nilable(Dependabot::Source),
          repo_contents_path: T.nilable(String),
          credentials: T::Array[Dependabot::Credential],
          reject_external_code: T::Boolean,
          options: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(
        dependency_files:,
        source: nil,
        repo_contents_path: nil,
        credentials: [],
        reject_external_code: false,
        options: {}
      )
        super

        raise ArgumentError, "repo_contents_path is required" if repo_contents_path.nil?

        set_go_environment_variables
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new

        if workspace?
          parse_workspace_dependencies(dependency_set)
        else
          required_packages.each do |hsh|
            next if skip_dependency?(hsh)

            dependency_set << dependency_from_details(hsh)
          end
        end

        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          begin
            Ecosystem.new(
              name: ECOSYSTEM,
              package_manager: package_manager,
              language: language
            )
          end,
          T.nilable(Dependabot::Ecosystem)
        )
      end

      # Utility method to allow collaborators to check other go commands inside the parsed project's context
      sig { params(command: String).returns(String) }
      def run_in_parsed_context(command)
        SharedHelpers.in_a_temporary_repo_directory(T.must(source&.directory), repo_contents_path) do |path|
          # Create a fake empty module for local modules that are not inside the repository.
          # This allows us to run go commands that require all modules to be present.
          local_replacements.each do |_, stub_path|
            FileUtils.mkdir_p(stub_path)
            FileUtils.touch(File.join(stub_path, "go.mod"))
          end

          File.write("go.mod", go_mod_content)

          stdout, stderr, status = Open3.capture3(command)
          handle_parser_error(path, stderr) unless status.success?

          stdout
        end
      end

      private

      sig { void }
      def set_go_environment_variables
        set_goenv_variable
        set_goproxy_variable
        set_goprivate_variable
        set_gonoproxy_variable
        set_gonosumdb_variable
      end

      sig { void }
      def set_goenv_variable
        return unless go_env

        env_file = T.must(go_env)
        File.write(env_file.name, sanitize_go_env_content(T.must(env_file.content)))
        ENV["GOENV"] = Pathname.new(env_file.name).realpath.to_s
      end

      # Go's GOENV file format does not support shell-style quoting, but users
      # commonly write values like GOPROXY="https://..." which Go reads literally
      # (including the quotes), causing URL parse failures. Strip surrounding
      # matching " or ' from each value.
      sig { params(content: String).returns(String) }
      def sanitize_go_env_content(content)
        content.gsub(
          /
            ^          # start of line
            ([^=\n]+)  # key: one or more chars that are not = or newline
            =          # separator
            (["'])     # opening quote, captured for backreference
            (.*)       # value
            \2         # closing quote must match opening
            $          # end of line
          /x,
          '\1=\3'
        )
      end

      sig { void }
      def set_goprivate_variable
        return if go_env&.content&.include?("GOPRIVATE")
        return if go_env&.content&.include?("GOPROXY")
        return if goproxy_credentials.any?

        goprivate = T.cast(options.fetch(:goprivate, "*"), T.nilable(String))
        ENV["GOPRIVATE"] = goprivate if goprivate
      end

      # GONOPROXY explicitly controls which module paths skip the proxy.
      # Setting this overrides GOPRIVATE's default for proxy decisions, letting
      # us keep GOPRIVATE=* (to skip sumdb for unknown enterprise orgs) while
      # still routing public modules through proxy.golang.org. The literal
      # value "none" matches no module paths — see Go's mod_gonoproxy.txt test.
      sig { void }
      def set_gonoproxy_variable
        return if go_env_includes_any?(%w(GONOPROXY GOPRIVATE GOPROXY))
        return if goproxy_credentials.any?

        gonoproxy = T.cast(options.fetch(:gonoproxy, nil), T.nilable(String))
        ENV["GONOPROXY"] = gonoproxy if gonoproxy
      end

      # GONOSUMDB explicitly controls which module paths skip checksum DB
      # verification. Setting this overrides GOPRIVATE's default for sumdb,
      # letting us narrow the scope independently of proxy routing.
      sig { void }
      def set_gonosumdb_variable
        return if go_env_includes_any?(%w(GONOSUMDB GOPRIVATE))

        gonosumdb = T.cast(options.fetch(:gonosumdb, nil), T.nilable(String))
        ENV["GONOSUMDB"] = gonosumdb if gonosumdb
      end

      sig { params(keys: T::Array[String]).returns(T::Boolean) }
      def go_env_includes_any?(keys)
        content = go_env&.content
        return false unless content

        keys.any? { |key| content.index(key) }
      end

      sig { void }
      def set_goproxy_variable
        return if go_env&.content&.include?("GOPROXY")
        return if goproxy_credentials.empty?

        urls = goproxy_credentials.filter_map { |cred| cred["url"] }
        ENV["GOPROXY"] = "#{urls.join(',')},direct"
      end

      sig { returns(T::Array[Dependabot::Credential]) }
      def goproxy_credentials
        @goproxy_credentials ||= T.let(
          credentials.select do |cred|
            cred["type"] == "goproxy_server"
          end,
          T.nilable(T::Array[Dependabot::Credential])
        )
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(T.must(go_toolchain_version)),
          T.nilable(Dependabot::GoModules::PackageManager)
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        @language ||= T.let(
          go_version ? Language.new(T.must(go_version)) : nil,
          T.nilable(Dependabot::GoModules::Language)
        )
      end

      sig { returns(T.nilable(String)) }
      def go_version
        @go_version ||= T.let(
          go_mod&.content&.match(/^go\s(\d+\.\d+(.\d+)*)/)&.captures&.first,
          T.nilable(String)
        )
      end

      sig { returns(T.nilable(String)) }
      def go_toolchain_version
        @go_toolchain_version ||= T.let(
          begin
            # Checks version based on the GOTOOLCHAIN in ENV
            version = SharedHelpers.run_shell_command("go version")
            version.match(/go\s*(\d+\.\d+(.\d+)*)/)&.captures&.first
          end,
          T.nilable(String)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_mod
        @go_mod ||= T.let(get_original_file("go.mod"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_env
        @go_env ||= T.let(get_original_file("go.env"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_work
        @go_work ||= T.let(get_original_file("go.work"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T::Boolean) }
      def workspace?
        !go_work.nil?
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def all_go_mods
        @all_go_mods ||= T.let(
          if go_work
            workspace_mod_names = GoWorkParser.use_paths(T.must(T.must(go_work).content)).map do |path|
              path == "." ? "go.mod" : "#{path}/go.mod"
            end
            dependency_files.select { |f| workspace_mod_names.include?(f.name) }
          else
            dependency_files.select { |f| f.name.end_with?("go.mod") }
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).void }
      def parse_workspace_dependencies(dependency_set)
        all_go_mods.each do |mod_file|
          parse_single_module(mod_file).each do |dep|
            dependency_set << dep
          end
        end
      end

      sig { params(mod_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_single_module(mod_file)
        SharedHelpers.in_a_temporary_directory do |path|
          File.write("go.mod", mod_file.content)

          command = "go mod edit -json"
          stdout, stderr, status = Open3.capture3(command)
          handle_parser_error(path, stderr, file_path: mod_file.path) unless status.success?

          parsed = GoModManifest.from_json(stdout, file_path: mod_file.path)

          parsed.requirements.filter_map do |entry|
            next if skip_dependency_in_manifest?(entry, parsed)

            source = { type: "default", source: entry.path }
            version = entry.version&.sub(/^v?/, "")

            reqs = [{
              requirement: entry.version,
              file: mod_file.name,
              source: source,
              groups: []
            }]

            Dependency.new(
              name: entry.path,
              version: version,
              requirements: entry.indirect ? [] : reqs,
              package_manager: "go_modules"
            )
          end
        end
      end

      sig { params(dep: GoModManifest::RequirementEntry, mod_manifest: GoModManifest).returns(T::Boolean) }
      def skip_dependency_in_manifest?(dep, mod_manifest)
        return true if dependency_is_replaced_in?(dep, mod_manifest)

        path_uri = URI.parse("https://#{dep.path}")
        !path_uri.host&.include?(".")
      rescue URI::InvalidURIError
        false
      end

      sig { params(details: GoModManifest::RequirementEntry, mod_manifest: GoModManifest).returns(T::Boolean) }
      def dependency_is_replaced_in?(details, mod_manifest)
        mod_manifest.replacements.any? do |replacement|
          replacement.old.path == details.path &&
            (replacement.old.version.nil? || replacement.old.version == details.version)
        end
      end

      sig { override.void }
      def check_required_files
        raise "No go.mod or go.work!" unless go_mod || go_work
      end

      sig { params(details: GoModManifest::RequirementEntry).returns(Dependabot::Dependency) }
      def dependency_from_details(details)
        source = { type: "default", source: details.path }
        version = details.version&.sub(/^v?/, "")

        reqs = [{
          requirement: details.version,
          file: go_mod&.name,
          source: source,
          groups: []
        }]

        Dependency.new(
          name: details.path,
          version: version,
          requirements: details.indirect ? [] : reqs,
          package_manager: "go_modules"
        )
      end

      sig { returns(T::Array[GoModManifest::RequirementEntry]) }
      def required_packages
        @required_packages ||=
          T.let(
            GoModManifest.from_json(
              run_in_parsed_context("go mod edit -json"),
              file_path: T.must(go_mod).path
            ).requirements,
            T.nilable(T::Array[GoModManifest::RequirementEntry])
          )
      end

      sig { returns(T::Hash[String, String]) }
      def local_replacements
        @local_replacements ||=
          # Find all the local replacements, and return them with a stub path
          # we can use in their place. Using generated paths is safer as it
          # means we don't need to worry about references to parent
          # directories, etc.
          T.let(
            ReplaceStubber.new(T.must(repo_contents_path)).stub_paths(manifest, go_mod&.directory),
            T.nilable(T::Hash[String, String])
          )
      end

      sig { returns(GoModManifest) }
      def manifest
        @manifest ||=
          T.let(
            SharedHelpers.in_a_temporary_directory do |path|
              File.write("go.mod", go_mod&.content)

              # Parse the go.mod to get a JSON representation of the replace
              # directives
              command = "go mod edit -json"

              stdout, stderr, status = Open3.capture3(command)
              handle_parser_error(path, stderr) unless status.success?

              GoModManifest.from_json(stdout, file_path: T.must(go_mod).path)
            end,
            T.nilable(GoModManifest)
          )
      end

      sig { returns(T.nilable(String)) }
      def go_mod_content
        local_replacements.reduce(go_mod&.content) do |body, (path, stub_path)|
          body&.sub(path, stub_path)
        end
      end

      sig { params(path: T.any(Pathname, String), stderr: String, file_path: T.nilable(String)).returns(T.noreturn) }
      def handle_parser_error(path, stderr, file_path: nil)
        msg = stderr.gsub(path.to_s, "").strip
        resolved_path = file_path || go_mod&.path || go_work&.path || "go.mod"
        raise Dependabot::DependencyFileNotParseable.new(resolved_path, msg)
      end

      sig { params(dep: GoModManifest::RequirementEntry).returns(T::Boolean) }
      def skip_dependency?(dep)
        # Updating replaced dependencies is not supported
        return true if dependency_is_replaced(dep)

        path_uri = URI.parse("https://#{dep.path}")
        !path_uri.host&.include?(".")
      rescue URI::InvalidURIError
        false
      end

      sig { params(details: GoModManifest::RequirementEntry).returns(T::Boolean) }
      def dependency_is_replaced(details)
        # Mark dependency as replaced if the requested dependency has a
        # "replace" directive and that either has the same version, or no
        # version mentioned. This mimics the behaviour of go get -u, and
        # prevents that we change dependency versions without any impact since
        # the actual version that is being imported is defined by the replace
        # directive.
        dependency_is_replaced_in?(details, manifest)
      end
    end
  end
end

Dependabot::FileParsers
  .register("go_modules", Dependabot::GoModules::FileParser)
