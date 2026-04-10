# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "open3"
require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
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
          # Parse dependencies from all workspace modules
          workspace_dependencies.each do |dep|
            dependency_set << dep
          end
        else
          # Single module mode
          required_packages.each do |hsh|
            unless skip_dependency?(hsh) # rubocop:disable Style/Next

              dep = dependency_from_details(hsh)
              dependency_set << dep
            end
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

          # Only write go.mod if it exists (might be workspace-only)
          File.write("go.mod", go_mod_content) if go_mod_content

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
      end

      sig { void }
      def set_goenv_variable
        return unless go_env

        env_file = T.must(go_env)
        File.write(env_file.name, env_file.content)
        ENV["GOENV"] = Pathname.new(env_file.name).realpath.to_s
      end

      sig { void }
      def set_goprivate_variable
        return if go_env&.content&.include?("GOPRIVATE")
        return if go_env&.content&.include?("GOPROXY")
        return if goproxy_credentials.any?

        goprivate = options.fetch(:goprivate, "*")
        ENV["GOPRIVATE"] = goprivate if goprivate
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
      def workspace_go_mods
        return [] unless workspace?

        dependency_files.select { |f| f.name.end_with?("go.mod") && f.name != "go.mod" }
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def workspace_dependencies
        deps = Dependabot::FileParsers::Base::DependencySet.new

        # Get all go.mod files from workspace modules
        all_go_mods = workspace_go_mods
        # Include root go.mod only if it exists (workspace root might not have go.mod)
        all_go_mods << T.must(go_mod) if go_mod

        raise "No go.mod files found in workspace!" if all_go_mods.empty?

        all_go_mods.each do |mod_file|
          # Parse each module's dependencies
          module_deps = parse_module_dependencies(mod_file)
          module_deps.each { |dep| deps << dep }
        end

        deps.dependencies
      end

      sig { params(mod_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_module_dependencies(mod_file)
        # Parse go.mod file to get dependencies
        SharedHelpers.in_a_temporary_directory do |path|
          File.write("go.mod", mod_file.content)

          # Create stub modules for local replacements
          # Derive the actual module directory from the file name
          # e.g., "tools/go.mod" -> "/tools", "go.mod" -> "/"
          module_directory = File.dirname(mod_file.name)
          module_directory = "/" if module_directory == "."
          module_directory = "/#{module_directory}" unless module_directory.start_with?("/")

          # Parse manifest using consistent error handling
          stdout, stderr, status = Open3.capture3("go mod edit -json")
          handle_parser_error(path, stderr) unless status.success?
          manifest = JSON.parse(stdout)

          local_replacements = ReplaceStubber.new(T.must(repo_contents_path))
                                             .stub_paths(manifest, module_directory)

          local_replacements.each do |_, stub_path|
            FileUtils.mkdir_p(stub_path)
            FileUtils.touch(File.join(stub_path, "go.mod"))
          end

          # Get required packages using consistent error handling
          stdout, stderr, status = Open3.capture3("go mod edit -json")
          handle_parser_error(path, stderr) unless status.success?
          packages = JSON.parse(stdout)["Require"] || []

          packages.filter_map do |hsh|
            next if skip_dependency?(hsh)

            # Create dependency with the module file reference
            source = { type: "default", source: hsh["Path"] }
            version = hsh["Version"]&.sub(/^v?/, "")

            reqs = [{
              requirement: hsh["Version"],
              file: mod_file.name,
              source: source,
              groups: []
            }]

            Dependency.new(
              name: hsh["Path"],
              version: version,
              requirements: hsh["Indirect"] ? [] : reqs,
              package_manager: "go_modules"
            )
          end
        end
      end

      sig { override.void }
      def check_required_files
        raise "No go.mod or go.work!" unless go_mod || go_work
      end

      sig { params(details: T::Hash[String, T.untyped]).returns(Dependabot::Dependency) }
      def dependency_from_details(details)
        source = { type: "default", source: details["Path"] }
        version = details["Version"]&.sub(/^v?/, "")

        reqs = [{
          requirement: details["Version"],
          file: go_mod&.name,
          source: source,
          groups: []
        }]

        Dependency.new(
          name: details["Path"],
          version: version,
          requirements: details["Indirect"] ? [] : reqs,
          package_manager: "go_modules"
        )
      end

      sig { returns(T::Array[T::Hash[String, T.untyped]]) }
      def required_packages
        @required_packages ||=
          T.let(
            JSON.parse(run_in_parsed_context("go mod edit -json"))["Require"] || [],
            T.nilable(T::Array[T::Hash[String, T.untyped]])
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

      sig { returns(T::Hash[String, T.untyped]) }
      def manifest
        @manifest ||=
          T.let(
            begin
              # In workspace-only mode (no root go.mod), return empty manifest
              return {} unless go_mod

              SharedHelpers.in_a_temporary_directory do |path|
                File.write("go.mod", go_mod&.content)

                # Parse the go.mod to get a JSON representation of the replace
                # directives
                command = "go mod edit -json"

                stdout, stderr, status = Open3.capture3(command)
                handle_parser_error(path, stderr) unless status.success?

                JSON.parse(stdout)
              end
            end,
            T.nilable(T::Hash[String, T.untyped])
          )
      end

      sig { returns(T.nilable(String)) }
      def go_mod_content
        return nil unless go_mod

        local_replacements.reduce(go_mod&.content) do |body, (path, stub_path)|
          body&.sub(path, stub_path)
        end
      end

      sig { params(path: T.any(Pathname, String), stderr: String).returns(T.noreturn) }
      def handle_parser_error(path, stderr)
        msg = stderr.gsub(path.to_s, "").strip
        # Use go.work path if no go.mod exists (workspace-only repos)
        file_path = go_mod&.path || go_work&.path || "go.mod"
        raise Dependabot::DependencyFileNotParseable.new(file_path, msg)
      end

      sig { params(dep: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def skip_dependency?(dep)
        # Updating replaced dependencies is not supported
        return true if dependency_is_replaced(dep)

        path_uri = URI.parse("https://#{dep['Path']}")
        !path_uri.host&.include?(".")
      rescue URI::InvalidURIError
        false
      end

      sig { params(details: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def dependency_is_replaced(details)
        # Mark dependency as replaced if the requested dependency has a
        # "replace" directive and that either has the same version, or no
        # version mentioned. This mimics the behaviour of go get -u, and
        # prevents that we change dependency versions without any impact since
        # the actual version that is being imported is defined by the replace
        # directive.
        if manifest["Replace"]
          dep_replace = manifest["Replace"].find do |replace|
            replace["Old"]["Path"] == details["Path"] &&
              (!replace["Old"]["Version"] || replace["Old"]["Version"] == details["Version"])
          end

          return true if dep_replace
        end
        false
      end
    end
  end
end

Dependabot::FileParsers
  .register("go_modules", Dependabot::GoModules::FileParser)
