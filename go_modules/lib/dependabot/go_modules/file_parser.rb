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
      GIT_VERSION_REGEX = /^v\d+\.\d+\.\d+-.*-(?<sha>[0-9a-f]{12})$/.freeze

      def parse
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new

        required_packages.each do |dep|
          dependency_set << dependency_from_details(dep) unless dep["Indirect"]
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
          else { type: "default", source: details["Path"] }
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
              Dir.mkdir(stub_path) unless Dir.exist?(stub_path)
              FileUtils.touch(File.join(stub_path, "go.mod"))
            end

            File.write("go.mod", go_mod_content)

            command = "go mod edit -json"

            # Turn off the module proxy for now, as it's causing issues with
            # private git dependencies
            env = { "GOPRIVATE" => "*" }

            stdout, stderr, status = Open3.capture3(env, command)
            handle_parser_error(path, stderr) unless status.success?
            JSON.parse(stdout)["Require"] || []
          rescue Dependabot::DependencyFileNotResolvable
            # We sometimes see this error if a host times out.
            # In such cases, retrying (a maximum of 3 times) may fix it.
            retry_count ||= 0
            raise if retry_count >= 3

            retry_count += 1
            retry
          end
      end

      def local_replacements
        @local_replacements ||=
          SharedHelpers.in_a_temporary_directory do |path|
            File.write("go.mod", go_mod.content)

            # Parse the go.mod to get a JSON representation of the replace
            # directives
            command = "go mod edit -json"

            # Turn off the module proxy for now, as it's causing issues with
            # private git dependencies
            env = { "GOPRIVATE" => "*" }

            stdout, stderr, status = Open3.capture3(env, command)
            handle_parser_error(path, stderr) unless status.success?

            # Find all the local replacements, and return them with a stub path
            # we can use in their place. Using generated paths is safer as it
            # means we don't need to worry about references to parent
            # directories, etc.
            manifest = JSON.parse(stdout)
            ReplaceStubber.new(repo_contents_path).stub_paths(manifest, go_mod.directory)
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
          msg = e.message + " for #{dep['Path']}. Attempted to detect VCS "\
                            "because the version looks like a git revision: "\
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
    end
  end
end

Dependabot::FileParsers.
  register("go_modules", Dependabot::GoModules::FileParser)
