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

          def initialize(dependency:, dependency_files:, versions:)
            @dependency = dependency
            @dependency_files = dependency_files
            @versions = versions.
                        select { |v| v > version_class.new(dependency.version) }
          end

          def latest_resolvable_version(unlock_requirement:)
            unless %i(none own all).include?(unlock_requirement)
              raise "Invalid unlock setting: #{unlock_requirement}"
            end

            # Elm has no lockfile, no unlock essentially means
            # "let elm-package install whatever satisfies .requirements"
            if unlock_requirement == :none
              return version_class.new(dependency.version)
            end

            # Otherwise, we gotta check a few conditions to see if bumping
            # wouldn't also bump other deps in elm-package.json
            #
            # For Elm 0.18 we could just free the requirement
            #        (i.e. 0.0.0 <= v <= 999.999.999)
            # but what we got here is compatible with what we'll have to do
            # in Elm 0.19 where you only get exact dependencies
            versions.sort.reverse_each do |version|
              return version if can_update?(version, unlock_requirement)
            end

            # Fall back to returning the dependency's current version, which is
            # presumed to be resolvable
            version_class.new(dependency.version)
          end

          def updated_dependencies_after_full_unlock(version)
            deps_after_install = fetch_install_metadata(target_version: version)

            original_dependency_details.map do |original_dep|
              new_version = deps_after_install.fetch(original_dep.name)

              old_reqs = original_dep.requirements.map do |req|
                Dependabot::Utils::Elm::Requirement.new(req[:requirement])
              end

              next if old_reqs.all? { |req| req.satisfied_by?(new_version) }

              new_requirements =
                RequirementsUpdater.new(
                  requirements: original_dep.requirements,
                  latest_resolvable_version: new_version.to_s
                ).updated_requirements

              Dependency.new(
                name: original_dep.name,
                version: new_version.to_s,
                requirements: new_requirements,
                previous_version: original_dep.version,
                previous_requirements: original_dep.requirements,
                package_manager: original_dep.package_manager
              )
            end.compact
          end

          private

          attr_reader :dependency, :dependency_files, :versions

          def can_update?(version, unlock_requirement)
            deps_after_install = fetch_install_metadata(target_version: version)

            result = check_install_result(deps_after_install)

            # If the install was clean then we can definitely update
            return true if result == :clean_bump

            # Otherwise, we can still update if the result was a forced full
            # unlock and we're allowed to unlock other requirements
            return false unless unlock_requirement == :all
            result == :forced_full_unlock_bump
          end

          def fetch_install_metadata(target_version:)
            @install_cache ||= {}
            @install_cache[target_version.to_s] ||=
              SharedHelpers.in_a_temporary_directory do
                write_temporary_dependency_files(target_version: target_version)

                # Elm package install outputs a preview of the actions to be
                # performed. We can use this preview to calculate whether it
                # would do anything funny
                command = "yes n | elm-package install"
                response = run_shell_command(command)

                deps_after_install = CliParser.decode_install_preview(response)

                deps_after_install
              rescue SharedHelpers::HelperSubprocessFailed => error
                # 5) We bump our dep but elm-package blows up
                handle_elm_package_errors(error)
              end
          end

          def check_install_result(deps_after_install)
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

            version_after_install = deps_after_install.fetch(dependency.name)

            # 3) We bump our dep but actually elm-package doesn't bump it
            if version_after_install <= version_class.new(dependency.version)
              return :downgrade_bug
            end

            other_top_level_deps_bumped =
              original_dependency_details.
              reject { |dep| dep.name == dependency.name }.
              select do |dep|
                deps_after_install[dep.name] > version_class.new(dep.version)
              end

            # 2) We bump our dep and another dep is bumped
            return :forced_full_unlock_bump if other_top_level_deps_bumped.any?

            # 1) We bump our dep and no other dep is bumped
            :clean_bump
          end

          def run_shell_command(command)
            raw_response = nil
            IO.popen(command, err: %i(child out)) do |process|
              raw_response = process.read
            end

            # Raise an error with the output from the shell session if Elm
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

          def write_temporary_dependency_files(target_version:)
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)

              File.write(
                path,
                updated_elm_package_content(file.content, target_version)
              )
            end
          end

          def updated_elm_package_content(content, version)
            json = JSON.parse(content)

            new_requirement = RequirementsUpdater.new(
              requirements: dependency.requirements,
              latest_resolvable_version: version.to_s
            ).updated_requirements.first[:requirement]

            json["dependencies"][dependency.name] = new_requirement
            JSON.dump(json)
          end

          def original_dependency_details
            @original_dependency_details ||=
              FileParsers::Elm::ElmPackage.new(
                dependency_files: dependency_files,
                source: nil
              ).parse
          end

          def version_class
            Utils::Elm::Version
          end
        end
      end
    end
  end
end
