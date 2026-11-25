# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bazel/file_updater"
require "dependabot/bazel/file_parser/starlark_parser"

module Dependabot
  module Bazel
    class FileUpdater < Dependabot::FileUpdaters::Base
      class BzlmodFileUpdater
        extend T::Sig

        require_relative "lockfile_updater"

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            dependencies: T::Array[Dependabot::Dependency],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency_files:, dependencies:, credentials:)
          @dependency_files = dependency_files
          @dependencies = dependencies
          @credentials = credentials
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_module_files
          updated_files = T.let([], T::Array[Dependabot::DependencyFile])

          module_files.each do |file|
            updated_content = update_file_content(file)
            next if updated_content == T.must(file.content)

            updated_files << file.dup.tap { |f| f.content = updated_content }
          end

          if generate_lockfile?
            lockfile_updater = LockfileUpdater.new(
              dependency_files: dependency_files,
              dependencies: dependencies,
              credentials: credentials
            )

            updated_lockfile = lockfile_updater.updated_lockfile
            updated_files << updated_lockfile if updated_lockfile
          end

          updated_files
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def module_files
          @module_files ||= T.let(
            dependency_files.select { |f| f.name.end_with?("MODULE.bazel") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T::Boolean) }
        def generate_lockfile?
          dependency_files.any? { |f| f.name.end_with?("MODULE.bazel.lock") }
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def update_file_content(file)
          content = T.must(file.content).dup

          dependencies.each do |dependency|
            content = update_dependency_in_content(content, dependency)
          end

          content
        end

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_dependency_in_content(content, dependency)
          return content unless dependency.package_manager == "bazel"

          update_bazel_dep_version(content, dependency)
        end

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_bazel_dep_version(content, dependency)
          new_version = dependency.version
          return content unless new_version

          parser = FileParser::StarlarkParser.new(content)
          calls = parser.parse_function_calls
          replacements = T.let({}, T::Hash[T::Range[Integer], String])

          calls.each do |call|
            next unless call.name == "bazel_dep" && call.arguments["name"] == dependency.name

            replacement = version_replacement(content, parser, call, new_version)
            replacements[replacement[0]] = replacement[1] if replacement
          end

          replacements.sort_by { |range, _| -range.begin }.each_with_object(content.dup) do |(range, value), updated|
            updated[range] = value
          end
        end

        sig do
          params(
            content: String,
            parser: FileParser::StarlarkParser,
            call: FileParser::StarlarkParser::FunctionCall,
            new_version: String
          ).returns(T.nilable([T::Range[Integer], String]))
        end
        def version_replacement(content, parser, call, new_version)
          range = call.argument_ranges["version"]
          return unless range

          value = call.arguments["version"]
          if value.is_a?(FileParser::StarlarkParser::Identifier)
            assignment_range = parser.string_assignment_ranges[value.name]
            return unless assignment_range

            # Only the assignment and this use may reference a constant we rewrite.
            if T.must(parser.identifier_locations[value.name]).uniq.length == 2
              literal = T.must(content[assignment_range])
              quote = literal.start_with?('"""', "'''") ? literal[0, 3] : literal[0]
              return [assignment_range, "#{quote}#{new_version}#{quote}"]
            end
          elsif !value.is_a?(String)
            return
          end

          [range, "\"#{new_version}\""]
        end
      end
    end
  end
end
