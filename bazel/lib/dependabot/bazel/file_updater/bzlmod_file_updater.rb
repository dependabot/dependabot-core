# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bazel/file_updater"

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

          escaped_name = Regexp.escape(dependency.name)

          bazel_dep_pattern = /bazel_dep\s*\(([^)]+?)\)/mx

          content.gsub(bazel_dep_pattern) do |match|
            function_content = T.must(Regexp.last_match(1))

            if /name\s*=\s*["']#{escaped_name}["']/.match?(function_content)
              updated_function_content = function_content.gsub(
                /version\s*=\s*["'][^"']*["']/,
                "version = \"#{new_version}\""
              )
              "bazel_dep(#{updated_function_content})"
            else
              match
            end
          end
        end
      end
    end
  end
end
