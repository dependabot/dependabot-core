# frozen_string_literal: true

require "toml-rb"
require "dependabot/git_commit_checker"
require "dependabot/file_updaters/base"
require "dependabot/file_parsers/rust/cargo"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Rust
      class Cargo < Dependabot::FileUpdaters::Base
        require_relative "cargo/manifest_updater"
        require_relative "cargo/lockfile_updater"

        def self.updated_files_regex
          [
            /^Cargo\.toml$/,
            /^Cargo\.lock$/
          ]
        end

        def updated_dependency_files
          # Returns an array of updated files. Only files that have been updated
          # should be returned.
          updated_files = []

          manifest_files.each do |file|
            next unless file_changed?(file)
            updated_files <<
              updated_file(
                file: file,
                content: updated_manifest_content(file)
              )
          end

          if lockfile && updated_lockfile_content != lockfile.content
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          raise "No files changed!" if updated_files.empty?

          updated_files
        end

        private

        def check_required_files
          raise "No Cargo.toml!" unless get_original_file("Cargo.toml")
        end

        def updated_manifest_content(file)
          ManifestUpdater.new(
            dependencies: dependencies,
            manifest: file
          ).updated_manifest_content
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            LockfileUpdater.new(
              dependencies: dependencies,
              dependency_files: dependency_files,
              credentials: credentials
            ).updated_lockfile_content
        end

        def manifest_files
          @manifest_files ||=
            dependency_files.
            select { |f| f.name.end_with?("Cargo.toml") }.
            reject { |f| f.type == "path_dependency" }
        end

        def lockfile
          @lockfile ||= get_original_file("Cargo.lock")
        end
      end
    end
  end
end
