# typed: strong
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Deno
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/manifest_updater"
      require_relative "file_updater/lockfile_updater"

      MANIFEST_FILENAMES = T.let(%w(deno.json deno.jsonc).freeze, T::Array[String])

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        dependency_files.each do |file|
          next unless MANIFEST_FILENAMES.include?(file.name)

          new_content = update_manifest_content(file)
          next if new_content == file.content

          updated_files << updated_file(file: file, content: new_content)
        end

        if lockfile
          updated_files << updated_file(
            file: T.must(lockfile),
            content: lockfile_updater.updated_lockfile_content
          )
        end

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any? { |f| MANIFEST_FILENAMES.include?(f.name) }

        raise "No deno.json or deno.jsonc found!"
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          dependency_files.find { |f| f.name == "deno.lock" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(LockfileUpdater) }
      def lockfile_updater
        @lockfile_updater ||= T.let(
          LockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          ),
          T.nilable(LockfileUpdater)
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def update_manifest_content(file)
        ManifestUpdater.new(dependencies: dependencies, manifest: file).updated_manifest_content
      end
    end
  end
end

Dependabot::FileUpdaters.register("deno", Dependabot::Deno::FileUpdater)
