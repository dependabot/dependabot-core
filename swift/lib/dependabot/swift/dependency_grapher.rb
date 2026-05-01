# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/shared_helpers"
require "dependabot/swift/url_helpers"
require "dependabot/swift/xcode_file_helpers"

module Dependabot
  module Swift
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      extend T::Sig

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        if classic_spm_mode?
          package_resolved || T.must(package_manifest)
        else
          xcode_resolved_file
        end
      end

      private

      # Mirror the FileParser's mode selection: classic SPM takes precedence
      # when Package.swift is present, otherwise use Xcode SPM.
      sig { returns(T::Boolean) }
      def classic_spm_mode?
        !package_manifest.nil?
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def package_manifest
        return @package_manifest if defined?(@package_manifest)

        @package_manifest = T.let(
          dependency_files.find { |f| f.name == "Package.swift" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def package_resolved
        return @package_resolved if defined?(@package_resolved)

        @package_resolved = T.let(
          dependency_files.find { |f| f.name == "Package.resolved" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      # Returns the first Xcode-scoped Package.resolved, chosen deterministically
      # by filename to ensure consistent ownership when multiple Xcode projects exist.
      sig { returns(Dependabot::DependencyFile) }
      def xcode_resolved_file
        file = xcode_resolved_files.min_by(&:name)
        raise DependabotError, "No Package.swift or Xcode Package.resolved found." unless file

        file
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def xcode_resolved_files
        @xcode_resolved_files ||= T.let(
          dependency_files.select do |f|
            XcodeFileHelpers.xcode_resolved_path?(f.name) && !f.support_file?
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        return [] unless classic_spm_mode?

        dependency_names = @dependencies.map(&:name)
        package_relationships.fetch(dependency.name, []).select { |child| dependency_names.include?(child) }
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "swift"
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def package_relationships
        @package_relationships ||= T.let(
          fetch_package_relationships,
          T.nilable(T::Hash[String, T::Array[String]])
        )
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_package_relationships
        SharedHelpers.in_a_temporary_repo_directory(
          T.must(dependency_files.first).directory,
          file_parser.repo_contents_path
        ) do
          write_temporary_dependency_files

          SharedHelpers.with_git_configured(credentials: file_parser.credentials) do
            json = SharedHelpers.run_shell_command(
              "swift package show-dependencies --format json",
              stderr_to_stdout: false
            )
            parse_dependency_tree(JSON.parse(json))
          end
        end
      end

      sig { void }
      def write_temporary_dependency_files
        dependency_files.each do |file|
          next if file.support_file?

          File.write(file.name, file.content)
        end
      end

      # Walks the JSON tree from `swift package show-dependencies --format json`
      # and builds a map of parent_name -> [child_names].
      sig { params(data: T::Hash[String, T.untyped]).returns(T::Hash[String, T::Array[String]]) }
      def parse_dependency_tree(data)
        relationships = T.let({}, T::Hash[String, T::Array[String]])
        walk_tree(data, relationships)
        relationships
      end

      sig { params(node: T::Hash[String, T.untyped], relationships: T::Hash[String, T::Array[String]]).void }
      def walk_tree(node, relationships)
        parent_name = node_name(node)
        children = node.fetch("dependencies", [])

        return if children.empty?

        child_names = children.filter_map { |child| node_name(child) }
        relationships[parent_name] = child_names if parent_name

        children.each { |child| walk_tree(child, relationships) }
      end

      sig { params(node: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
      def node_name(node)
        url = node["url"]
        return nil unless url

        UrlHelpers.normalize_name(SharedHelpers.scp_to_standard(url))
      end
    end
  end
end

Dependabot::DependencyGraphers.register("swift", Dependabot::Swift::DependencyGrapher)
