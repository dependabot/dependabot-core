# typed: true
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/devcontainers/file_updater/config_updater"

module Dependabot
  module Devcontainers
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [
          /^\.?devcontainer\.json$/,
          /^\.?devcontainer-lock\.json$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        manifests.each do |manifest|
          requirement = dependency.requirements.find { |req| req[:file] == manifest.name }
          next unless requirement

          config_contents, lockfile_contents = update(manifest, requirement)

          updated_files << updated_file(file: manifest, content: config_contents) if file_changed?(manifest)

          lockfile = lockfile_for(manifest)

          updated_files << updated_file(file: lockfile, content: lockfile_contents) if lockfile && lockfile_contents
        end

        updated_files
      end

      private

      def dependency
        # TODO: Handle one dependency at a time
        dependencies.first
      end

      def check_required_files
        return if dependency_files.any?

        raise "No dev container configuration!"
      end

      def manifests
        @manifests ||= dependency_files.select do |f|
          f.name.end_with?("devcontainer.json")
        end
      end

      def lockfile_for(manifest)
        lockfile_name = lockfile_name_for(manifest)

        dependency_files.find do |f|
          f.name == lockfile_name
        end
      end

      def lockfile_name_for(manifest)
        basename = File.basename(manifest.name)
        lockfile_name = Utils.expected_lockfile_name(basename)

        manifest.name.delete_suffix(basename).concat(lockfile_name)
      end

      def update(manifest, requirement)
        ConfigUpdater.new(
          feature: dependency.name,
          requirement: requirement,
          manifest: manifest,
          repo_contents_path: repo_contents_path,
          credentials: credentials
        ).update
      end
    end
  end
end

Dependabot::FileUpdaters.register("devcontainers", Dependabot::Devcontainers::FileUpdater)
