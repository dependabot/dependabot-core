# frozen_string_literal: true

require "open3"
require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/go_modules/path_converter"
require "dependabot/go_modules/replace_stubber"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

module Dependabot
  module GoModules
    class FileParser < Dependabot::FileParsers::Base
      GIT_VERSION_REGEX = /^v\d+\.\d+\.\d+-.*-(?<sha>[0-9a-f]{12})$/

      def parse
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new

        required_packages.each do |dep|
          dependency_set << dependency_from_details(dep) unless skip_dependency?(dep)
        end

        dependency_set.dependencies
      end

      private

      def go_mod
        @go_mod ||= get_original_file("go.mod")
      end

      def check_required_files
        raise "No go.mod!" unless go_mod
      end

      def dependency_from_details(details)
        source =
          if rev_identifier?(details) then git_source(details)
          else
            { type: "default", source: details["Path"] }
          end

        version = details["Version"]&.sub(/^v?/, "")

        reqs = [{
          requirement: rev_identifier?(details) ? nil : details["Version"],
          file: go_mod.name,
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

      def required_packages
        @required_packages ||=
          SharedHelpers.in_a_temporary_directory do |path|
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
          end
      end

      def local_replacements
        @local_replacements ||=
          # Find all the local replacements, and return them with a stub path
          # we can use in their place. Using generated paths is safer as it
          # means we don't need to worry about references to parent
          # directories, etc.
          ReplaceStubber.new(repo_contents_path).stub_paths(manifest, go_mod.directory)
      end

      def manifest
        @manifest ||=
          SharedHelpers.in_a_temporary_directory do |path|
            File.write("go.mod", go_mod.content)

            # Parse the go.mod to get a JSON representation of the replace
            # directives
            command = "go mod edit -json"

            stdout, stderr, status = Open3.capture3(command)
            handle_parser_error(path, stderr) unless status.success?

            JSON.parse(stdout)
          end
      end

      def go_mod_content
        local_replacements.reduce(go_mod.content) do |body, (path, stub_path)|
          body.sub(path, stub_path)
        end
      end

      def handle_parser_error(path, stderr)
        msg = stderr.gsub(path.to_s, "").strip
        raise Dependabot::DependencyFileNotParseable.new(go_mod.path, msg)
      end

      def rev_identifier?(dep)
        dep["Version"]&.match?(GIT_VERSION_REGEX)
      end

      def git_source(dep)
        url = PathConverter.git_url_for_path(dep["Path"])

        # Currently, we have no way of knowing whether the commit tagged
        # is being used because a branch is being followed or because a
        # particular ref is in use. We *assume* that a particular ref is in
        # use (which means we'll only propose updates when its included in
        # a release)
        {
          type: "git",
          url: url || dep["Path"],
          ref: git_revision(dep),
          branch: nil
        }
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        if e.message == "Cannot detect VCS"
          # if the dependency is locally replaced, this is not a fatal error
          return { type: "default", source: dep["Path"] } if dependency_has_local_replacement(dep)

          msg = e.message + " for #{dep['Path']}. Attempted to detect VCS " \
                            "because the version looks like a git revision: " \
                            "#{dep['Version']}"
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        raise
      end

      def git_revision(dep)
        raw_version = dep.fetch("Version")
        return raw_version unless raw_version.match?(GIT_VERSION_REGEX)

        raw_version.match(GIT_VERSION_REGEX).named_captures.fetch("sha")
      end

      def skip_dependency?(dep)
        # Updating replaced dependencies is not supported
        return true if dependency_is_replaced(dep)

        path_uri = URI.parse("https://#{dep['Path']}")
        !path_uri.host.include?(".")
      rescue URI::InvalidURIError
        false
      end

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

      def dependency_has_local_replacement(details)
        if manifest["Replace"]
          has_local_replacement = manifest["Replace"].find do |replace|
            replace["New"]["Path"].start_with?("./", "../") &&
              replace["Old"]["Path"] == details["Path"]
          end

          return true if has_local_replacement
        end
        false
      end
    end
  end
end

Dependabot::FileParsers.
  register("go_modules", Dependabot::GoModules::FileParser)
