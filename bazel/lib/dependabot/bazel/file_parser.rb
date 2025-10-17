# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/bazel/version"
require "dependabot/bazel/file_parser/starlark_parser"
require "dependabot/errors"

module Dependabot
  module Bazel
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      REPOSITORY_REFERENCE = "@([^/]+)"

      DEPS_REGEX = /
        deps\s*=\s*                           # deps parameter assignment
        \[                                    # Opening bracket
        \s*                                   # Optional whitespace
        ([^\]]+)                              # Capture group 1: content within brackets
        \]                                    # Closing bracket
      /mx

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependencies = T.let([], T::Array[Dependabot::Dependency])

        module_files.each do |file|
          dependencies.concat(parse_module_file(file))
        end

        workspace_files.each do |file|
          dependencies.concat(parse_workspace_file(file))
        end

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

      sig { returns(T.nilable(String)) }
      def bazel_version
        bazelversion_file = dependency_files.find { |f| f.name == ".bazelversion" }
        bazelversion_file&.content&.strip
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_module_file(file)
        dependencies = T.let([], T::Array[Dependabot::Dependency])
        content = file.content
        return dependencies unless content

        parser = StarlarkParser.new(content)
        function_calls = parser.parse_function_calls

        function_calls.each do |func_call|
          next unless func_call.name == "bazel_dep"

          name = func_call.arguments["name"]
          version = func_call.arguments["version"]

          next unless name && version

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

        parser = StarlarkParser.new(content)
        function_calls = parser.parse_function_calls

        function_calls.each do |func_call|
          dependency = case func_call.name
                       when "http_archive"
                         parse_http_archive_dependency(func_call, file)
                       when "git_repository"
                         parse_git_repository_dependency(func_call, file)
                       end

          dependencies << dependency if dependency
        end

        dependencies
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

        url = urls.is_a?(Array) ? urls.first : urls
        return nil unless name && url

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

        version = tag || commit
        return nil unless name && version

        Dependabot::Dependency.new(
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

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_build_file(file)
        # Parses BUILD files for load() statements and dependency references
        dependencies = T.let([], T::Array[Dependabot::Dependency])
        content = file.content
        return dependencies unless content

        parser = StarlarkParser.new(content)
        function_calls = parser.parse_function_calls

        dependencies.concat(parse_load_statements(function_calls, file))
        dependencies.concat(parse_dependency_references(content, file))

        dependencies
      end

      sig do
        params(
          function_calls: T::Array[StarlarkParser::FunctionCall],
          file: Dependabot::DependencyFile
        ).returns(T::Array[Dependabot::Dependency])
      end
      def parse_load_statements(function_calls, file)
        dependencies = T.let([], T::Array[Dependabot::Dependency])

        function_calls.each do |func_call|
          next unless func_call.name == "load"

          first_arg = func_call.positional_arguments.first
          next unless first_arg.is_a?(String)

          match = first_arg.match(%r{^@([^/]+)})
          next unless match

          repo_name = match[1]
          next unless repo_name
          next if repo_name == "bazel_tools"

          dependencies << Dependabot::Dependency.new(
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

        dependencies
      end

      sig do
        params(
          content: String,
          file: Dependabot::DependencyFile
        ).returns(T::Array[Dependabot::Dependency])
      end
      def parse_dependency_references(content, file)
        dependencies = T.let([], T::Array[Dependabot::Dependency])

        content.scan(DEPS_REGEX) do |deps_content|
          deps_content_str = deps_content[0] # Extract the string from the array

          dependency_reference_pattern = /"#{REPOSITORY_REFERENCE}/o

          deps_content_str.scan(dependency_reference_pattern) do |repo_name|
            repo_name = repo_name[0]
            next if repo_name == "bazel_tools"

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
        # GitHub archive URLs: /archive/v1.2.3.tar.gz
        github_archive_pattern = %r{
          github\.com/[^/]+/[^/]+/archive/  # GitHub archive path
          (?:v?([^/]+))                     # Capture version (with optional 'v' prefix)
          \.(?:tar\.gz|tar\.bz2|zip)$       # Archive extension
        }x

        # GitHub release URLs: /releases/download/v1.2.3/
        github_release_pattern = %r{
          github\.com/[^/]+/[^/]+/releases/download/  # GitHub releases path
          (?:v?([^/]+))/                              # Capture version (with optional 'v' prefix)
        }x

        # Generic version pattern in URLs
        generic_version_pattern = %r{
          /(?:v?([0-9]+(?:\.[0-9]+)*(?:[+-][^/]*)?))  # Capture semantic version
          (?:\.tar\.gz|\.zip|$)                       # Optional archive extension or end
        }x

        if url =~ github_archive_pattern
          return Regexp.last_match(1)
        elsif url =~ github_release_pattern
          return Regexp.last_match(1)
        elsif url =~ generic_version_pattern
          return Regexp.last_match(1)
        end

        nil
      end
    end
  end
end

Dependabot::FileParsers.register("bazel", Dependabot::Bazel::FileParser)
