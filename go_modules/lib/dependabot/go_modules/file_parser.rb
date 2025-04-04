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

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        set_gotoolchain_env

        dependency_set = Dependabot::FileParsers::Base::DependencySet.new

        required_packages.each do |dep|
          dependency_set << dependency_from_details(dep) unless skip_dependency?(dep)
        end

        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(begin
          set_gotoolchain_env
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          )
        end, T.nilable(Dependabot::Ecosystem))
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(T.must(go_toolchain_version)),
          T.nilable(Dependabot::GoModules::PackageManager)
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        @language ||= T.let(begin
          Language.new(go_version)
        end, T.nilable(Dependabot::GoModules::Language))
      end

      sig { returns(String) }
      def go_version
        @go_version ||= T.let(T.must(go_mod&.content&.match(/^go\s(\d+\.\d+(.\d+)*)/)&.captures&.first),
                              T.nilable(String))
      end

      sig { returns(T.nilable(String)) }
      def go_toolchain_version
        @go_toolchain_version ||= T.let(begin
          # Checks version based on the GOTOOLCHAIN in ENV
          version = SharedHelpers.run_shell_command("go version")
          version.match(/go\s*(\d+\.\d+(.\d+)*)/)&.captures&.first
        end, T.nilable(String))
      end

      # set GOTOOLCHAIN=local+auto if go version >= 1.21
      sig { void }
      def set_gotoolchain_env
        go_directive = go_mod&.content&.match(/^go\s(\d+\.\d+)/)&.captures&.first
        return ENV["GOTOOLCHAIN"] = ENV.fetch("GO_LEGACY") unless go_directive

        go_version = Dependabot::GoModules::Version.new(go_directive)
        ENV["GOTOOLCHAIN"] = if go_version >= "1.21"
                               "local+auto"
                             else
                               ENV.fetch("GO_LEGACY")
                             end
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_mod
        @go_mod ||= T.let(get_original_file("go.mod"), T.nilable(Dependabot::DependencyFile))
      end

      sig { override.void }
      def check_required_files
        raise "No go.mod!" unless go_mod
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
          T.let(SharedHelpers.in_a_temporary_directory do |path|
            # Create a fake empty module for each local module so that
            # `go mod edit` works, even if some modules have been `replace`d with
            # a local module that we don't have access to.
            local_replacements.each do |_, stub_path|
              FileUtils.mkdir_p(stub_path)
              FileUtils.touch(File.join(stub_path, "go.mod"))
            end

            File.write("go.mod", go_mod_content)

            command = "go mod edit -json"

            stdout, stderr, status = Open3.capture3(command)
            handle_parser_error(path, stderr) unless status.success?
            JSON.parse(stdout)["Require"] || []
          end, T.nilable(T::Array[T::Hash[String, T.untyped]]))
      end

      sig { returns(T::Hash[String, String]) }
      def local_replacements
        @local_replacements ||=
          # Find all the local replacements, and return them with a stub path
          # we can use in their place. Using generated paths is safer as it
          # means we don't need to worry about references to parent
          # directories, etc.
          T.let(ReplaceStubber.new(repo_contents_path).stub_paths(manifest, go_mod&.directory),
                T.nilable(T::Hash[String, String]))
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def manifest
        @manifest ||=
          T.let(SharedHelpers.in_a_temporary_directory do |path|
                  File.write("go.mod", go_mod&.content)

                  # Parse the go.mod to get a JSON representation of the replace
                  # directives
                  command = "go mod edit -json"

                  stdout, stderr, status = Open3.capture3(command)
                  handle_parser_error(path, stderr) unless status.success?

                  JSON.parse(stdout)
                end, T.nilable(T::Hash[String, T.untyped]))
      end

      sig { returns(T.nilable(String)) }
      def go_mod_content
        local_replacements.reduce(go_mod&.content) do |body, (path, stub_path)|
          body&.sub(path, stub_path)
        end
      end

      sig { params(path: T.any(Pathname, String), stderr: String).returns(T.noreturn) }
      def handle_parser_error(path, stderr)
        msg = stderr.gsub(path.to_s, "").strip
        raise Dependabot::DependencyFileNotParseable.new(T.must(go_mod).path, msg)
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
