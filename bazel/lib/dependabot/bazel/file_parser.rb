# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/bazel/version"
require "dependabot/bazel/package_manager"
require "dependabot/bazel/language"
require "dependabot/ecosystem"
require "dependabot/errors"

module Dependabot
  module Bazel
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require_relative "file_parser/starlark_parser"

      REPOSITORY_REFERENCE = %r{@([^/]+)}

      DEPS_REGEX = /deps\s*=\s*\[\s*([^\]]+)\]/mx

      GITHUB_ARCHIVE_PATTERN = %r{
          github\.com/[^/]+/[^/]+/archive/  # GitHub archive path
          (?:v?([^/]+))                     # Capture version (with optional 'v' prefix)
          \.(?:tar\.gz|tar\.bz2|zip)$       # Archive extension
        }x

      GITHUB_RELEASE_PATTERN = %r{
          github\.com/[^/]+/[^/]+/releases/download/  # GitHub releases path
          (?:v?([^/]+))/                              # Capture version (with optional 'v' prefix)
        }x

      GENERIC_VERSION_PATTERN = %r{
          /(?:v?([0-9]+(?:\.[0-9]+)*(?:[+-][^/]*)?))  # Capture semantic version
          (?:\.tar\.gz|\.zip|$)                       # Optional archive extension or end
        }x

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new
        dependency_set += module_dependencies
        dependency_set += workspace_dependencies
        dependency_set += build_dependencies

        dependencies = dependency_set.dependencies

        dependencies.uniq { |dep| [dep.name, dep.version] }
      end

      sig { override.returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(
            detected_version: bazel_version || DEFAULT_BAZEL_VERSION,
            raw_version: bazel_version
          ),
          T.nilable(Ecosystem::VersionManager)
        )
      end

      sig { returns(Ecosystem::VersionManager) }
      def language
        @language ||= T.let(
          Language.new(bazel_version || DEFAULT_BAZEL_VERSION),
          T.nilable(Ecosystem::VersionManager)
        )
      end

      sig { returns(DependencySet) }
      def module_dependencies
        dependency_set = DependencySet.new

        module_files.each do |file|
          dependency_set += parse_module_file(file)
        end

        dependency_set
      end

      sig { returns(DependencySet) }
      def workspace_dependencies
        dependency_set = DependencySet.new

        workspace_files.each do |file|
          dependency_set += parse_workspace_file(file)
        end

        dependency_set
      end

      sig { returns(DependencySet) }
      def build_dependencies
        dependency_set = DependencySet.new

        build_files.each do |file|
          dependency_set += parse_build_file(file)
        end

        dependency_set
      end

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

      sig { returns(T.nilable(String)) }
      def bazel_version
        bazelversion_file = dependency_files.find { |f| f.name == ".bazelversion" }
        bazelversion_file&.content&.strip
      end

      sig { params(file: Dependabot::DependencyFile).returns(DependencySet) }
      def parse_module_file(file)
        dependency_set = DependencySet.new
        content = file.content
        return dependency_set unless content

        parser = StarlarkParser.new(content)
        function_calls = parser.parse_function_calls

        function_calls.each do |func_call|
          next unless func_call.name == "bazel_dep"

          name = func_call.arguments["name"]
          version = func_call.arguments["version"]

          next unless name.is_a?(String) && version.is_a?(String) && !name.empty? && !version.empty?

          dependency_set << Dependabot::Dependency.new(
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

        dependency_set
      end

      sig { params(file: Dependabot::DependencyFile).returns(DependencySet) }
      def parse_workspace_file(file)
        dependency_set = DependencySet.new
        content = file.content
        return dependency_set unless content

        parser = StarlarkParser.new(content)
        function_calls = parser.parse_function_calls

        function_calls.each do |func_call|
          dependency = case func_call.name
                       when "http_archive"
                         parse_http_archive_dependency(func_call, file)
                       when "git_repository"
                         parse_git_repository_dependency(func_call, file)
                       end

          dependency_set << dependency if dependency
        end

        dependency_set
      end

      sig do
        params(
          func_call: StarlarkParser::FunctionCall,
          file: Dependabot::DependencyFile
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def parse_http_archive_dependency(func_call, file)
        name = func_call.arguments["name"]
        urls = func_call.arguments["urls"]

        return nil unless name.is_a?(String)

        url = urls.is_a?(Array) ? urls.first : urls
        return nil unless url.is_a?(String)

        version = extract_version_from_url(url)
        return nil unless version

        Dependabot::Dependency.new(
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

      sig do
        params(
          func_call: StarlarkParser::FunctionCall,
          file: Dependabot::DependencyFile
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def parse_git_repository_dependency(func_call, file)
        name = func_call.arguments["name"]
        tag = func_call.arguments["tag"]
        commit = func_call.arguments["commit"]
        remote = func_call.arguments["remote"]

        return nil unless name.is_a?(String)

        version = tag || commit
        return nil unless version.is_a?(String)

        Dependabot::Dependency.new(
          name: name,
          version: version,
          requirements: [
            {
              file: file.name,
              requirement: version,
              groups: [],
              source: { type: "git_repository", tag: tag, commit: commit, remote: remote }
            }
          ],
          package_manager: "bazel"
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(DependencySet) }
      def parse_build_file(file)
        dependency_set = DependencySet.new
        content = file.content
        return dependency_set unless content

        parser = StarlarkParser.new(content)
        function_calls = parser.parse_function_calls

        dependency_set += parse_load_statements(function_calls, file)
        dependency_set += parse_dependency_references(content, file)

        dependency_set
      end

      sig do
        params(
          function_calls: T::Array[StarlarkParser::FunctionCall],
          file: Dependabot::DependencyFile
        ).returns(DependencySet)
      end
      def parse_load_statements(function_calls, file)
        dependency_set = DependencySet.new

        function_calls.each do |func_call|
          next unless func_call.name == "load"

          first_arg = func_call.positional_arguments.first
          next unless first_arg.is_a?(String)

          match = first_arg.match(%r{^@([^/]+)})
          next unless match

          repo_name = match[1]
          next unless repo_name
          next if repo_name == "bazel_tools"

          dependency_set << Dependabot::Dependency.new(
            name: repo_name,
            version: nil,
            requirements: [
              {
                file: file.name,
                requirement: nil,
                groups: ["load_references"],
                source: { type: "load_statement" }
              }
            ],
            package_manager: "bazel"
          )
        end

        dependency_set
      end

      sig do
        params(
          content: String,
          file: Dependabot::DependencyFile
        ).returns(DependencySet)
      end
      def parse_dependency_references(content, file)
        dependency_set = DependencySet.new

        content.scan(DEPS_REGEX) do |deps_content|
          deps_content_str = deps_content[0]

          deps_content_str.scan(REPOSITORY_REFERENCE) do |repo_name|
            repo_name = repo_name[0]
            next if repo_name == "bazel_tools"

            dependency_set << Dependabot::Dependency.new(
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

        dependency_set
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def extract_version_from_url(url)
        version_patterns.each do |pattern|
          match = url.match(pattern)
          return match[1] if match
        end

        nil
      end

      sig { returns(T::Array[Regexp]) }
      def version_patterns
        [
          GITHUB_ARCHIVE_PATTERN,
          GITHUB_RELEASE_PATTERN,
          GENERIC_VERSION_PATTERN
        ]
      end
    end
  end
end

Dependabot::FileParsers.register("bazel", Dependabot::Bazel::FileParser)
