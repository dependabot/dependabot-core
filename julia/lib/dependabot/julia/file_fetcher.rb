# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/julia/shared"

module Dependabot
  module Julia
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.returns(T::Array[Regexp]) }
      def self.required_files_in?(filenames)
        Shared::PROJECT_NAMES.any? do |name|
          filenames.any? { |f| Shared.file_match?(f, name) }
        end
      end

      private

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []

        project_files = fetch_project_files
        manifest_files = fetch_manifest_files

        if project_files.size > 1
          raise DependencyFileNotFound,
                "Multiple project files found in '#{directory}': "\
                "#{project_files.map(&:name).join(', ')}"
        end

        if manifest_files.size > 1
          raise DependencyFileNotFound,
                "Multiple manifest files found in '#{directory}': "\
                "#{manifest_files.map(&:name).join(', ')}"
        end

        fetched_files.concat(project_files)
        fetched_files.concat(manifest_files)

        check_required_files(fetched_files)
        fetched_files
      end

      def fetch_project_files
        # Use shared helper instead of direct array
        fetch_contiguous_files(Shared::PROJECT_NAMES.first)
      end

      def fetch_manifest_files
        version = SharedHelpers.run_shell_command("julia --version")
                             .match(/(\d+\.\d+)/)[1]

        # Try each manifest name in priority order
        Shared.manifest_names(version).each do |name|
          files = fetch_contiguous_files(name)
          return files unless files.empty?
        end

        []
      rescue StandardError
        fetch_contiguous_files("Manifest.toml")
      end

      sig { params(filenames: T::Array[DependencyFile]).void }
      def check_required_files(filenames)
        return if filenames.any? { |f| f.name.match?(Shared::PROJECT_REGEX) }

        path = Pathname.new(File.join(directory, "Project.toml")).cleanpath
        raise DependencyFileNotFound, path.to_s
      end
    end
  end
end

Dependabot::FileFetchers.register("julia", Dependabot::Julia::FileFetcher)
