# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/file_parsers/elm/elm_package"
require "dependabot/update_checkers/elm/elm_package"
require "dependabot/update_checkers/elm/elm_package/cli_parser"
require "dependabot/update_checkers/elm/elm_package/requirements_updater"
require "dependabot/utils/elm/requirement"

module Dependabot
  module UpdateCheckers
    module Elm
      class ElmPackage
        class VersionResolver
          class UnrecoverableState < StandardError; end
          def initialize(dependency:, dependency_files:,
                         versions:)
            @dependency = dependency
            @dependency_files = dependency_files
            @versions = keep_higher_versions(versions, dependency.version)
          end

          def latest_resolvable_version(unlock_requirement:)
            # Elm has no lockfile, no unlock essentially means
            # "let elm-package install whatever satisfies .requirements"
            return @dependency.version if
              !unlock_requirement ||
              unlock_requirement == :none

            # don't look further if no other versions
            return @dependency.version if @versions.empty?

            # Otherwise, we gotta check a few conditions to see if bumping
            # wouldn't also bump other deps in elm-package.json
            #
            # For Elm 0.18 we could just free the requirement
            #        (i.e. 0.0.0 <= v <= 999.999.999)
            # but what we got here is compatible with what we'll have to do
            # in Elm 0.19 where you only get exact dependencies
            last_version = @versions[-1]
            versions = @versions[0..-2]
            return last_version if can_update?(last_version, unlock_requirement)

            return dependency.version if versions.empty?
          end

          def updated_dependencies_after_full_unlock(version)
            deps_after_install, original_dependencies =
              simulate_install(version)

            original_dependencies.map do |original_dependency|
              update_unmet_requirements(
                original_dependency,
                deps_after_install
              )
            end
          end

          def update_unmet_requirements(original_dependency, deps_after_install)
            new_version = deps_after_install[original_dependency.name]
            # When using ranges (1.0.0 <= v < 2.0.0) we put a guess
            # 1.999.999 version for original_dependency.version
            # We should use the concrete value we got from elm-package
            # in those cases.
            previous_version =
              [original_dependency.version, new_version].min.to_s

            # should never happen but
            msg = "Dependency disappeared after update"
            raise UnrecoverableState, msg unless new_version

            original_reqs = original_dependency.requirements.map do |req|
              Dependabot::Utils::Elm::Requirement.new(req[:requirement])
            end

            new_requirements =
              if original_reqs.all? { |req| req.satisfied_by?(new_version) }
                original_dependency.requirements
              else
                RequirementsUpdater.new(
                  requirements: original_dependency.requirements,
                  latest_resolvable_version: new_version.to_s
                ).updated_requirements
              end

            Dependency.new(
              name: original_dependency.name,
              version: new_version.to_s,
              requirements: new_requirements,
              previous_version: previous_version,
              previous_requirements: original_dependency.requirements,
              package_manager: original_dependency.package_manager
            )
          end

          private

          attr_reader :dependency, :dependency_files

          def keep_higher_versions(versions, lowest_version)
            versions.select { |v| v > lowest_version }
          end

          def can_update?(version, unlock_requirement)
            deps_after_install, original_dependencies =
              simulate_install(version)

            result = install_result(original_dependencies,
                                    deps_after_install)

            if unlock_requirement == :own
              result == :clean_bump
            else
              %i(clean_bump forced_full_unlock_bump).include?(result)
            end
          end

          def simulate_install(version)
            @install_cache ||= {}
            @install_cache[version] ||=
              SharedHelpers.in_a_temporary_directory do
                write_temporary_dependency_files_with(
                  dependency.name, dependency.requirements, version
                )

                # Elm package install outputs a preview of the actions to be
                # performed. We can use this preview to calculate whether it
                # would do anything funny
                command = "yes n | elm-package install"
                response = run_shell_command(command)

                deps_after_install = CliParser.decode_install_preview(response)

                [deps_after_install, original_dependency_details]
              rescue SharedHelpers::HelperSubprocessFailed => error
                # 5) We bump our dep but elm-package blows up
                handle_elm_package_errors(error)
              end
          end

          def original_dependency_details
            @original_dependency_details ||=
              FileParsers::Elm::ElmPackage.new(
                dependency_files: dependency_files,
                source: nil
              ).parse
          end

          def install_result(original_dependencies, deps_after_install)
            # This can go one of 5 ways:
            # 1) We bump our dep and no other dep is bumped
            # 2) We bump our dep and another dep is bumped too
            #    Scenario: NoRedInk/datetimepicker bump to 3.0.2 also
            #              bumps elm-css to 14
            # 3) We bump our dep but actually elm-package doesn't bump it
            #    Scenario: elm-css bump to 14 but datetimepicker is at 3.0.1
            # 4) We bump our dep but elm-package just says
            #    "Packages configured successfully!"
            #    Narrator: they weren't
            #    Scenario: impossible dependency (i.e. elm-css 999.999.999)
            #              a <= v < b where a is greater than latest version
            # 5) We bump our dep but elm-package blows up (not handled here)
            #    Scenario: rtfeldman/elm-css 14 && rtfeldman/hashed-class 1.0.0
            #              I'm not sure what's different from this scenario
            #              to 3), why it blows up instead of just rolling
            #              elm-css back to version 9 which is what
            #              hashed-class requires

            # 4) We bump our dep but elm-package just says
            #    "Packages configured successfully!"
            return :empty_elm_stuff_bug if deps_after_install.empty?

            version_after_install = deps_after_install[dependency.name]

            # 3) We bump our dep but actually elm-package doesn't bump it
            return :downgrade_bug if version_after_install <= dependency.version

            original_dependencies =
              original_dependencies.reject do |original_dependency|
                original_dependency.name == dependency.name
              end
            original_dependencies =
              original_dependencies.map { |a| [a.name, a.version] }.to_h

            # Remove transitive dependencies not found in elm-package.json
            deps_after_install =
              deps_after_install.
              select do |key, _val|
                key != dependency.name && original_dependencies.include?(key)
              end

            # 2) We bump our dep and another dep is bumped
            other_dep_bumped = deps_after_install.any? do |k, new_version|
              original_dependencies.key?(k) &&
                original_dependencies[k] <= new_version
            end

            return :forced_full_unlock_bump if other_dep_bumped

            # 1) We bump our dep and no other dep is bumped
            :clean_bump
          end

          def run_shell_command(command)
            raw_response = nil
            IO.popen(command, err: %i(child out)) do |process|
              raw_response = process.read
            end

            # Raise an error with the output from the shell session if Cargo
            # returns a non-zero status
            return raw_response if $CHILD_STATUS.success?
            raise SharedHelpers::HelperSubprocessFailed.new(
              raw_response,
              command
            )
          end

          def handle_elm_package_errors(error)
            if error.message.include?("I cannot find a set of packages that " \
                                      "works with your constraints")
              raise Dependabot::DependencyFileNotResolvable, error.message
            end

            # I don't know any other errors
            raise error
          end

          def write_temporary_dependency_files_with(
            dependency_name, requirements, version
          )
            @dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)

              # TODO: optimize this to not decode and reencode every time
              File.write(path, swap_version(file.content, dependency_name,
                                            requirements, version))
            end
          end

          def swap_version(content, dependency_name, requirements, version)
            json = JSON.parse(content)

            new_requirement = RequirementsUpdater.new(
              requirements: requirements,
              latest_resolvable_version: version.to_s
            ).updated_requirements.first[:requirement]

            json["dependencies"][dependency_name] = new_requirement
            JSON.dump(json)
          end
        end
      end
    end
  end
end
