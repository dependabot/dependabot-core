# frozen_string_literal: true

require "dependabot/npm_and_yarn/update_checker/registry_finder"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class FileUpdater
      class PnpmLockfileUpdater
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
        end

        def updated_pnpm_lock_content(pnpm_lock_file)
          @updated_pnpm_lock_content ||= {}
          return @updated_pnpm_lock_content[pnpm_lock_file.name] if @updated_pnpm_lock_content[pnpm_lock_file.name]

          updated_pnpm_lock(pnpm_lock_file)
        end

        def updated_pnpm_lock(pnpm_lock)
          original_path = Dir.pwd
          Dir.chdir(ENV["PACKAGES_CACHE_FOLDER"].to_s.strip)
          write_temporary_dependency_files
          lockfile_name = Pathname.new(pnpm_lock.name).basename.to_s
          path = Pathname.new(pnpm_lock.name).dirname.to_s
          response = run_current_rush_update(
            path: path,
            lockfile_name: lockfile_name
          )
          Dir.chdir(original_path)

          raise "Failed to update #{lockfile_name}: Content not changed." if response == pnpm_lock.content

          response
        end

        # TODO: Currently works only for a single file (pnpms's shrinkwrap.yaml/pnpm-lock.yaml). Update the params to take a list of file paths that need to be reread
        # after we run rush update.
        def run_rush_updater(path:, lockfile_name:)
          SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path,
            function: "rush:update",
            args: [
              Dir.pwd,
              path + "/" + lockfile_name
            ]
          )
        end

        def run_current_rush_update(path:, lockfile_name:)
          run_rush_updater(
            path: path,
            lockfile_name: lockfile_name
          )
        end

        def write_temporary_dependency_files
          # Copy updated dependency files to a temp folder
          @dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)

            # Update package.json files. Copy others as is
            updated_content =
              if file.name.end_with?("package.json") && top_level_dependencies.any?
                pkg_json = JSON.parse(updated_package_json_content(file))

                # strip "bin" from package.json - This prevents failures due to missing files during link step of "rush update"
                pkg_json.delete("bin")
                JSON.pretty_generate(pkg_json)
              else
                file.content
              end

            File.write(file.name, updated_content)
          end
        end

        def top_level_dependencies
          @dependencies.select(&:top_level?)
        end

        def npmrc_content
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).npmrc_content
        end

        def updated_package_json_content(file)
          @updated_package_json_content ||= {}
          @updated_package_json_content[file.name] ||=
            PackageJsonUpdater.new(
              package_json: file,
              dependencies: @dependencies
            ).updated_package_json.content
        end
      end
    end
  end
end
