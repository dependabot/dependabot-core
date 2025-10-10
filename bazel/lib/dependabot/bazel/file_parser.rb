# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/bazel/version"
require "dependabot/errors"

module Dependabot
  module Bazel
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      # Regular expressions for parsing different dependency types
      BAZEL_DEP_REGEX = /bazel_dep\(\s*name\s*=\s*"([^"]+)"\s*,\s*version\s*=\s*"([^"]+)"/m
      HTTP_ARCHIVE_REGEX = /http_archive\(\s*name\s*=\s*"([^"]+)"\s*,(?:[^}])*?urls\s*=\s*\[[^\]]*"([^"]*)"[^\]]*\]/m
      GIT_REPOSITORY_REGEX = /git_repository\(\s*name\s*=\s*"([^"]+)"\s*,(?:[^}])*?(?:tag\s*=\s*"([^"]+)"|commit\s*=\s*"([^"]+)")/m
      LOAD_REGEX = /load\(\s*"@([^\/]+)(?:\/\/([^"]*))?"[^)]*\)/
      DEPS_REGEX = /deps\s*=\s*\[\s*([^\]]+)\]/m

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependencies = T.let([], T::Array[Dependabot::Dependency])

        # Parse MODULE.bazel files (Bzlmod dependencies)
        module_files.each do |file|
          dependencies.concat(parse_module_file(file))
        end

        # Parse WORKSPACE files (legacy dependencies)
        workspace_files.each do |file|
          dependencies.concat(parse_workspace_file(file))
        end

        # Parse BUILD files for load statements and external references
        build_files.each do |file|
          dependencies.concat(parse_build_file(file))
        end

        dependencies.uniq { |dep| [dep.name, dep.version] }
      end

      private

      sig { override.void }
      def check_required_files
        return if module_files.any? || workspace_files.any?

        raise Dependabot::DependencyFileNotFound, "No MODULE.bazel or WORKSPACE file found!"
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def module_files
        @module_files ||= T.let(
          dependency_files.select { |f| f.name.end_with?("MODULE.bazel") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def workspace_files
        @workspace_files ||= T.let(
          dependency_files.select { |f| f.name == "WORKSPACE" || f.name.end_with?("WORKSPACE.bazel") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def build_files
        @build_files ||= T.let(
          dependency_files.select { |f| f.name == "BUILD" || f.name.end_with?("BUILD.bazel") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_module_file(file)
        dependencies = T.let([], T::Array[Dependabot::Dependency])
        content = file.content
        return dependencies unless content

        # Parse bazel_dep() declarations
        content.scan(BAZEL_DEP_REGEX) do |name, version|
          dependencies << Dependabot::Dependency.new(
            name: name,
            version: version,
            requirements: [
              {
                file: file.name,
                requirement: version,
                groups: [],
                source: nil
              }
            ],
            package_manager: "bazel"
          )
        end

        dependencies
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_workspace_file(file)
        dependencies = T.let([], T::Array[Dependabot::Dependency])
        content = file.content
        return dependencies unless content

        # Parse http_archive() declarations
        content.scan(HTTP_ARCHIVE_REGEX) do |name, url|
          version = extract_version_from_url(url)
          next unless version

          dependencies << Dependabot::Dependency.new(
            name: name,
            version: version,
            requirements: [
              {
                file: file.name,
                requirement: version,
                groups: [],
                source: { type: "http_archive", url: url }
              }
            ],
            package_manager: "bazel"
          )
        end

        # Parse git_repository() declarations
        content.scan(GIT_REPOSITORY_REGEX) do |name, tag, commit|
          version = tag || commit
          next unless version

          dependencies << Dependabot::Dependency.new(
            name: name,
            version: version,
            requirements: [
              {
                file: file.name,
                requirement: version,
                groups: [],
                source: { type: "git_repository", tag: tag, commit: commit }
              }
            ],
            package_manager: "bazel"
          )
        end

        dependencies
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_build_file(file)
        dependencies = T.let([], T::Array[Dependabot::Dependency])
        content = file.content
        return dependencies unless content

        # Parse load() statements for external repository references
        content.scan(LOAD_REGEX) do |repo_name, _path|
          # Only include external repositories (those starting with @)
          next if repo_name == "bazel_tools" # Skip built-in tools

          # For BUILD file references, we don't have explicit versions
          # so we mark them as dependency references without specific versions
          dependencies << Dependabot::Dependency.new(
            name: repo_name,
            version: nil,
            requirements: [
              {
                file: file.name,
                requirement: nil,
                groups: ["load"],
                source: { type: "load_statement" }
              }
            ],
            package_manager: "bazel"
          )
        end

        # Parse deps attributes for external repository references
        content.scan(DEPS_REGEX) do |deps_content|
          deps_content.scan(/"@([^\/]+)/) do |repo_name|
            repo_name = repo_name[0]
            next if repo_name == "bazel_tools" # Skip built-in tools

            dependencies << Dependabot::Dependency.new(
              name: repo_name,
              version: nil,
              requirements: [
                {
                  file: file.name,
                  requirement: nil,
                  groups: ["deps"],
                  source: { type: "dependency_reference" }
                }
              ],
              package_manager: "bazel"
            )
          end
        end

        dependencies
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def extract_version_from_url(url)
        # Try to extract version from common URL patterns
        # GitHub releases: https://github.com/owner/repo/archive/v1.2.3.tar.gz
        if url.match(%r{github\.com/[^/]+/[^/]+/archive/(?:v?([^/]+))\.})
          return Regexp.last_match(1)
        end

        # GitHub releases: https://github.com/owner/repo/releases/download/v1.2.3/file.tar.gz
        if url.match(%r{github\.com/[^/]+/[^/]+/releases/download/(?:v?([^/]+))/})
          return Regexp.last_match(1)
        end

        # Generic version patterns in URL
        if url.match(%r{/(?:v?([0-9]+(?:\.[0-9]+)*(?:[+-][^/]*)?))(?:\.tar\.gz|\.zip|$)})
          return Regexp.last_match(1)
        end

        nil
      end
    end
  end
end

Dependabot::FileParsers.register("bazel", Dependabot::Bazel::FileParser)
