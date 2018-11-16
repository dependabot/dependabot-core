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
        class Elm19VersionResolver
          class UnrecoverableState < StandardError; end

          def initialize(dependency:, dependency_files:)
            @dependency = dependency
            @dependency_files = dependency_files
          end

          def latest_resolvable_version(unlock_requirement:)
            unless %i(none own all).include?(unlock_requirement)
              raise "Invalid unlock setting: #{unlock_requirement}"
            end

            # Elm has no lockfile, so we will never create an update PR if
            # unlock requirements are `none`. Just return the current version.
            return current_version if unlock_requirement == :none

            # Otherwise, we gotta check a few conditions to see if bumping
            # wouldn't also bump other deps in elm-package.json
            fetch_latest_resolvable_version(unlock_requirement)
          end

          def updated_dependencies_after_full_unlock
            changed_deps = install_metadata

            original_dependency_details.map do |original_dep|
              new_version = changed_deps.fetch(original_dep.name, nil)
              next unless new_version

              old_reqs = original_dep.requirements.map do |req|
                requirement_class.new(req[:requirement])
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

          attr_reader :dependency, :dependency_files

          def fetch_latest_resolvable_version(unlock_requirement)
            changed_deps = install_metadata

            result = check_install_result(changed_deps)
            version_after_install = changed_deps.fetch(dependency.name)

            # If the install was clean then we can definitely update
            return version_after_install if result == :clean_bump

            # Otherwise, we can still update if the result was a forced full
            # unlock and we're allowed to unlock other requirements
            return version_after_install if unlock_requirement == :all

            current_version
          end

          def check_install_result(changed_deps)
            original_dependency_names =
              original_dependency_details.select(&:top_level?).map(&:name)

            other_deps_bumped =
              changed_deps.
              keys.
              reject { |name| name == dependency.name }.
              select { |n| original_dependency_names.include?(n) }

            return :forced_full_unlock_bump if other_deps_bumped.any?

            :clean_bump
          end

          def install_metadata
            @install_metadata ||=
              SharedHelpers.in_a_temporary_directory do
                write_temporary_dependency_files

                # Elm package install outputs a preview of the actions to be
                # performed. We can use this preview to calculate whether it
                # would do anything funny
                command = "yes n | elm19 install #{dependency.name}"
                response = run_shell_command(command)

                CliParser.decode_install_preview(response)
              rescue SharedHelpers::HelperSubprocessFailed => error
                # 5) We bump our dep but elm blows up
                handle_elm_errors(error)
              end
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

          def handle_elm_errors(error)
            if error.message.include?("OLD DEPENDENCIES") ||
               error.message.include?("BAD JSON")
              raise Dependabot::DependencyFileNotResolvable, error.message
            end

            # Raise any unrecognised errors
            raise error
          end

          def write_temporary_dependency_files
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)

              File.write(path, updated_elm_json_content(file.content))
            end
          end

          def updated_elm_json_content(content)
            json = JSON.parse(content)

            # Delete the dependency from the elm.json, so that we can use
            # `elm install <dependency_name>` to generate the install plan
            %w(dependencies test-dependencies).each do |type|
              if json.dig(type, dependency.name)
                json[type].delete(dependency.name)
              end

              %w(direct indirect).each do |category|
                if json.dig(type, category, dependency.name)
                  json[type][category].delete(dependency.name)
                end
              end
            end

            # Delete all indirect dependencies
            %w(dependencies test-dependencies).each do |type|
              json[type]["indirect"] = {} if json.dig(type, "indirect")
            end

            json["source-directories"] = []

            JSON.dump(json)
          end

          def original_dependency_details
            @original_dependency_details ||=
              FileParsers::Elm::ElmPackage.new(
                dependency_files: dependency_files,
                source: nil
              ).parse
          end

          def current_version
            return unless dependency.version

            version_class.new(dependency.version)
          end

          def version_class
            Utils::Elm::Version
          end

          def requirement_class
            Utils::Elm::Requirement
          end
        end
      end
    end
  end
end
