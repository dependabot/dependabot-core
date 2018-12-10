# frozen_string_literal: true

require "open3"
require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/utils/go/path_converter"
require "dependabot/errors"
require "dependabot/file_parsers/base"

module Dependabot
  module GoModules
    class FileParser < Dependabot::FileParsers::Base
      GIT_VERSION_REGEX = /^v\d+\.\d+\.\d+-.*-(?<sha>[0-9a-f]{12})$/.freeze

      def parse
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new

        i = 0
        chunks = module_info(go_mod).lines.
                 group_by { |line| line == "{\n" ? i += 1 : i }
        deps = chunks.values.map { |chunk| JSON.parse(chunk.join) }

        deps.each do |dep|
          # The project itself appears in this list as "Main"
          next if dep["Main"]

          dependency = dependency_from_details(dep)
          dependency_set << dependency if dependency
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
          package_manager: "dep"
        )
      end

      def module_info(go_mod)
        @module_info ||=
          SharedHelpers.in_a_temporary_directory do |path|
            SharedHelpers.with_git_configured(credentials: credentials) do
              File.write("go.mod", go_mod.content)

              command = "GO111MODULE=on go mod edit -print > /dev/null"
              command += " && GO111MODULE=on go list -m -json all"
              stdout, stderr, status = Open3.capture3(command)
              handle_parser_error(path, stderr) unless status.success?
              stdout
            end
          end
      end

      def handle_parser_error(path, stderr)
        case stderr
        when /go: .*: unknown revision/
          line = stderr.lines.grep(/unknown revision/).first
          raise Dependabot::DependencyFileNotResolvable, line.strip
        when /go: .*: unrecognized import path/
          line = stderr.lines.grep(/unrecognized import/).first
          raise Dependabot::DependencyFileNotResolvable, line.strip
        when /go: errors parsing go.mod/
          msg = stderr.gsub(path.to_s, "").strip
          raise Dependabot::DependencyFileNotParseable.new(go_mod.path, msg)
        else
          msg = stderr.gsub(path.to_s, "").strip
          raise Dependabot::DependencyFileNotParseable.new(go_mod.path, msg)
        end
      end

      def rev_identifier?(dep)
        dep["Version"]&.match?(GIT_VERSION_REGEX)
      end

      def git_source(dep)
        url = Utils::Go::PathConverter.git_url_for_path(dep["Path"])

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
      end

      def git_revision(dep)
        raw_version = dep.fetch("Version")
        return raw_version unless raw_version.match?(GIT_VERSION_REGEX)

        raw_version.match(GIT_VERSION_REGEX).named_captures.fetch("sha")
      end
    end
  end
end
