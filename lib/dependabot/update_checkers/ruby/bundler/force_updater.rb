# frozen_string_literal: true

require "bundler_definition_version_patch"
require "bundler_git_source_patch"

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/update_checkers/ruby/bundler/requirements_updater"
require "dependabot/file_parsers/ruby/bundler"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler
        class ForceUpdater
          def initialize(dependency:, dependency_files:, credentials:,
                         target_version:)
            @dependency       = dependency
            @dependency_files = dependency_files
            @credentials      = credentials
            @target_version   = target_version
          end

          def updated_dependencies
            @updated_dependencies ||= force_update
          end

          private

          attr_reader :dependency, :dependency_files, :credentials,
                      :target_version

          def force_update
            in_a_temporary_bundler_context do
              other_updates = []

              begin
                definition = build_definition(other_updates: other_updates)
                definition.resolve_remotely!
                specs = definition.resolve
                dependencies_from([dependency] + other_updates, specs)
              rescue ::Bundler::VersionConflict => error
                # TODO: Not sure this won't unlock way too many things...
                new_dependencies_to_unlock =
                  new_dependencies_to_unlock_from(
                    error: error,
                    already_unlocked: other_updates
                  )

                raise if new_dependencies_to_unlock.none?
                other_updates += new_dependencies_to_unlock
                retry
              end
            end
          rescue SharedHelpers::ChildProcessFailed => error
            raise_unresolvable_error(error)
          end

          #########################
          # Bundler context setup #
          #########################

          def in_a_temporary_bundler_context
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                # Remove installed gems from the default Rubygems index
                ::Gem::Specification.all = []

                # Set auth details
                credentials.each do |cred|
                  ::Bundler.settings.set_command_option(
                    cred["host"],
                    cred["token"] || "#{cred['username']}:#{cred['password']}"
                  )
                end

                yield
              end
            end
          end

          def new_dependencies_to_unlock_from(error:, already_unlocked:)
            error.cause.conflicts.values.
              flat_map { |conflict| conflict.requirement_trees.map(&:first) }.
              reject { |dep| already_unlocked.include?(dep.name) }.
              reject { |dep| dep.name == dependency.name }.
              uniq
          end

          def raise_unresolvable_error(error)
            msg = error.error_class + " with message: " + error.error_message
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          def build_definition(other_updates:)
            gems_to_unlock = other_updates.map(&:name) + [dependency.name]
            definition = ::Bundler::Definition.build(
              "Gemfile",
              lockfile&.name,
              gems: gems_to_unlock
            )

            # Remove the Gemfile / gemspec requirements on the gems we're
            # unlocking (i.e., completely unlock them)
            gems_to_unlock.each do |gem_name|
              unlock_gem(definition: definition, gem_name: gem_name)
            end

            # Set the requirement for the gem we're forcing an update of
            new_req = Gem::Requirement.create("= #{target_version}")
            definition.dependencies.
              find { |d| d.name == dependency.name }.
              instance_variable_set(:@requirement, new_req)

            definition
          end

          def unlock_gem(definition:, gem_name:)
            dep = definition.dependencies.find { |d| d.name == gem_name }
            version = definition.locked_gems.specs.
                      find { |d| d.name == gem_name }.version

            dep&.instance_variable_set(
              :@requirement,
              Gem::Requirement.create(">= #{version}")
            )
          end

          def original_dependencies
            @original_dependencies ||=
              FileParsers::Ruby::Bundler.new(
                dependency_files: dependency_files,
                credentials: credentials,
                repo: nil
              ).parse
          end

          def dependencies_from(updated_deps, specs)
            updated_deps.map do |dep|
              original_dep =
                original_dependencies.find { |d| d.name == dep.name }
              spec = specs.find { |d| d.name == dep.name }
              Dependency.new(
                name: dep.name,
                version: spec.version.to_s,
                requirements:
                  RequirementsUpdater.new(
                    requirements: original_dep.requirements,
                    existing_version: original_dep.version,
                    updated_source:
                      original_dep.requirements.
                        find { |r| r.fetch(:source) }&.
                        fetch(:source),
                    latest_version: spec.version.to_s,
                    latest_resolvable_version: spec.version.to_s
                  ).updated_requirements,
                previous_version: original_dep.version,
                previous_requirements: original_dep.requirements,
                package_manager: original_dep.package_manager
              )
            end
          end

          def gemfile
            dependency_files.find { |f| f.name == "Gemfile" }
          end

          def lockfile
            dependency_files.find { |f| f.name == "Gemfile.lock" }
          end

          def write_temporary_dependency_files
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, file.content)
            end
          end
        end
      end
    end
  end
end
