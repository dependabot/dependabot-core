# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/devcontainers/file_updater/config_updater"

module Dependabot
  module Devcontainers
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.params(_: T::Boolean).returns(T::Array[Regexp]) }
      def self.updated_files_regex(_ = false)
        [
          /^\.?devcontainer\.json$/,
          /^\.?devcontainer-lock\.json$/
        ]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        manifests.each do |manifest|
          requirement = dependency.requirements.find { |req| req[:file] == manifest.name }
          next unless requirement

          config_contents, lockfile_contents = update(manifest, requirement)

          updated_files << updated_file(file: manifest, content: T.must(config_contents)) if file_changed?(manifest)

          lockfile = lockfile_for(manifest)

          updated_files << updated_file(file: lockfile, content: lockfile_contents) if lockfile && lockfile_contents
        end

        updated_files
      end

      private

      sig { returns(Dependabot::Dependency) }
      def dependency
        # TODO: Handle one dependency at a time
        T.must(dependencies.first)
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No dev container configuration!"
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def manifests
        @manifests ||= T.let(
          dependency_files.select do |f|
            f.name.end_with?("devcontainer.json")
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { params(manifest: Dependabot::DependencyFile).returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile_for(manifest)
        lockfile_name = lockfile_name_for(manifest)

        dependency_files.find do |f|
          f.name == lockfile_name
        end
      end

      sig { params(manifest: Dependabot::DependencyFile).returns(String) }
      def lockfile_name_for(manifest)
        basename = File.basename(manifest.name)
        lockfile_name = Utils.expected_lockfile_name(basename)

        manifest.name.delete_suffix(basename).concat(lockfile_name)
      end

      sig do
        params(
          manifest: Dependabot::DependencyFile,
          requirement: T::Hash[Symbol, T.untyped]
        )
          .returns(T::Array[String])
      end
      def update(manifest, requirement)
        ConfigUpdater.new(
          feature: dependency.name,
          requirement: requirement[:requirement],
          version: T.must(dependency.version),
          manifest: manifest,
          repo_contents_path: T.must(repo_contents_path),
          credentials: credentials
        ).update
      end
    end
  end
end

Dependabot::FileUpdaters.register("devcontainers", Dependabot::Devcontainers::FileUpdater)
