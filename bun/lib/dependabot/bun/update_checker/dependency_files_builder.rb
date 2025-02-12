# typed: true
# frozen_string_literal: true

require "dependabot/bun/file_updater/npmrc_builder"
require "dependabot/bun/file_updater/package_json_preparer"

module Dependabot
  module Bun
    class UpdateChecker
      class DependencyFilesBuilder
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
        end

        def write_temporary_dependency_files
          write_lockfiles

          File.write(".npmrc", npmrc_content)

          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, prepared_package_json_content(file))
          end
        end

        def bun_locks
          @bun_locks ||=
            dependency_files
            .select { |f| f.name.end_with?("bun.lock") }
        end

        def root_bun_lock
          @root_bun_lock ||=
            dependency_files
            .find { |f| f.name == "bun.lock" }
        end

        def lockfiles
          [*bun_locks]
        end

        def package_files
          @package_files ||=
            dependency_files
            .select { |f| f.name.end_with?("package.json") }
        end

        private

        attr_reader :dependency
        attr_reader :dependency_files
        attr_reader :credentials

        def write_lockfiles
          bun_locks.each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, f.content)
          end
        end

        def prepared_package_json_content(file)
          Bun::FileUpdater::PackageJsonPreparer.new(
            package_json_content: file.content
          ).prepared_content
        end

        def npmrc_content
          Bun::FileUpdater::NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).npmrc_content
        end
      end
    end
  end
end
