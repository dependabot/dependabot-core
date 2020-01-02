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
                    if @updated_pnpm_lock_content[pnpm_lock_file.name]
                        return @updated_pnpm_lock_content[pnpm_lock_file.name]
                    end
            
                    new_content = updated_pnpm_lock(pnpm_lock_file)
            
                    # @updated_pnpm_lock_content[pnpm_lock_file.name] =
                    #     post_process_pnpm_lock_file(new_content)
                end


                def updated_pnpm_lock(pnpm_lock)
                    SharedHelpers.in_a_temporary_directory do
                    # write_temporary_dependency_files
                    lockfile_name = Pathname.new(pnpm_lock.name).basename.to_s
                    path = Pathname.new(pnpm_lock.name).dirname.to_s
                    updated_files = run_current_rush_update(
                        path: path,
                        lockfile_name: lockfile_name
                    )
                    updated_files.fetch(lockfile_name)
                    end
                #   rescue SharedHelpers::HelperSubprocessFailed => e
                #     handle_pnpm_lock_updater_error(e, pnpm_lock)
                end

                def run_rush_updater(path:, lockfile_name:) #, top_level_dependency_updates:)
                    puts "#{Dir.pwd}"
                    SharedHelpers.with_git_configured(credentials: @credentials) do
                        Dir.chdir(path) do
                            SharedHelpers.run_helper_subprocess(
                                command: NativeHelpers.helper_path,
                                function: "rush:update",
                                args: [
                                Dir.pwd
                                # top_level_dependency_updates
                                ]
                            )
                        end
                    end
                end

                def run_current_rush_update(path:, lockfile_name:)
                    # top_level_dependency_updates = top_level_dependencies.map do |d|
                    # {
                    #     name: d.name,
                    #     version: d.version,
                    #     requirements: requirements_for_path(d.requirements, path)
                    # }
                    # end
        
                    run_rush_updater(
                        path: path,
                        lockfile_name: lockfile_name,
                        # top_level_dependency_updates: top_level_dependency_updates
                    )
                end

                def write_temporary_dependency_files(update_package_json: true)
                    # write_lockfiles
        
                    # File.write(".npmrc", npmrc_content)
                    # File.write(".yarnrc", yarnrc_content) if yarnrc_specifies_npm_reg?
        
                    package_files.each do |file|
                        path = file.name
                        FileUtils.mkdir_p(Pathname.new(path).dirname)
            
                        updated_content =
                            if update_package_json && top_level_dependencies.any?
                                updated_package_json_content(file)
                            else
                                file.content
                            end
            
                        updated_content = replace_ssh_sources(updated_content)
            
                        # A bug prevents Yarn recognising that a directory is part of a
                        # workspace if it is specified with a `./` prefix.
                        updated_content = remove_workspace_path_prefixes(updated_content)
            
                        updated_content = sanitized_package_json_content(updated_content)
                        File.write(file.name, updated_content)
                    end
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
                        dependencies: top_level_dependencies
                        ).updated_package_json.content
                end
            end
        end
    end
end
