# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/lean"
require "dependabot/lean/lake/manifest_updater"

module Dependabot
  module Lean
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/^lean-toolchain$/, /^lake-manifest\.json$/]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        # Update toolchain file for Lean version updates
        updated_files.concat(updated_toolchain_files)

        # Update lake-manifest.json for Lake package updates
        updated_files.concat(updated_lake_manifest_files)

        updated_files
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_toolchain_files
        updated_files = []

        toolchain_file = dependency_files.find { |f| f.name == LEAN_TOOLCHAIN_FILENAME }
        return updated_files unless toolchain_file
        return updated_files unless toolchain_file_changed?(toolchain_file)

        updated_files << updated_file(
          file: toolchain_file,
          content: updated_toolchain_content(T.must(toolchain_file.content))
        )

        updated_files
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_lake_manifest_files
        updated_files = []

        manifest_file = dependency_files.find { |f| f.name == LAKE_MANIFEST_FILENAME }
        return updated_files unless manifest_file

        lake_deps = lake_package_dependencies
        return updated_files if lake_deps.empty?

        updater = Lake::ManifestUpdater.new(
          manifest_content: T.must(manifest_file.content),
          dependencies: lake_deps
        )

        updated_content = updater.updated_manifest_content
        return updated_files if updated_content == manifest_file.content

        updated_files << updated_file(
          file: manifest_file,
          content: updated_content
        )

        updated_files
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def lake_package_dependencies
        dependencies.select do |dep|
          source_details = dep.source_details
          source_details && source_details[:type] == "git"
        end
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def toolchain_dependencies
        dependencies.reject do |dep|
          source_details = dep.source_details
          source_details && source_details[:type] == "git"
        end
      end

      sig { params(content: String).returns(String) }
      def updated_toolchain_content(content)
        toolchain_deps = toolchain_dependencies
        return content if toolchain_deps.empty?

        dependency = T.must(toolchain_deps.first)
        previous_version = dependency.previous_version
        new_version = dependency.version

        return content unless previous_version && new_version

        content.gsub(
          "#{TOOLCHAIN_PREFIX}#{previous_version}",
          "#{TOOLCHAIN_PREFIX}#{new_version}"
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def toolchain_file_changed?(file)
        toolchain_deps = toolchain_dependencies
        return false if toolchain_deps.empty?

        dependency = T.must(toolchain_deps.first)
        previous_version = dependency.previous_version
        new_version = dependency.version

        return false unless previous_version && new_version
        return false if previous_version == new_version

        T.must(file.content).include?("#{TOOLCHAIN_PREFIX}#{previous_version}")
      end

      sig { override.void }
      def check_required_files
        has_toolchain = dependency_files.any? { |f| f.name == LEAN_TOOLCHAIN_FILENAME }
        has_manifest = dependency_files.any? { |f| f.name == LAKE_MANIFEST_FILENAME }

        return if has_toolchain || has_manifest

        raise Dependabot::DependencyFileNotFound.new(
          nil,
          "No #{LEAN_TOOLCHAIN_FILENAME} or #{LAKE_MANIFEST_FILENAME} found"
        )
      end
    end
  end
end

Dependabot::FileUpdaters.register("lean", Dependabot::Lean::FileUpdater)
