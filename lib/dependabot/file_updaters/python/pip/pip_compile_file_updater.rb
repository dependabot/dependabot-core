# frozen_string_literal: true

require "dependabot/file_updaters/python/pip"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Python
      class Pip
        class PipCompileFileUpdater
          require_relative "requirement_replacer"

          attr_reader :dependencies, :dependency_files, :credentials

          def initialize(dependencies:, dependency_files:, credentials:)
            @dependencies = dependencies
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def updated_dependency_files
            return @updated_dependency_files if @update_already_attempted

            @update_already_attempted = true
            @updated_dependency_files ||= fetch_updated_dependency_files
          end

          private

          def dependency
            # For now, we'll only ever be updating a single dependency
            dependencies.first
          end

          def fetch_updated_dependency_files
            SharedHelpers.in_a_temporary_directory do
              write_updated_dependency_files

              # Shell out to pip-compile, generate a new set of requirements.
              # This is slow, as pip-compile needs to do installs.
              cmd = "pyenv exec pip-compile -P #{dependency.name} "\
                    "#{source_pip_config_file_name}"
              run_command(cmd)

              dependency_files.map do |file|
                updated_content = File.read(file.name)
                next if updated_content == file.content

                file = file.dup
                file.content = updated_content
                file
              end.compact
            end
          end

          def run_command(command)
            raw_response = nil
            IO.popen(command, err: %i(child out)) do |process|
              raw_response = process.read
            end

            # Raise an error with the output from the shell session if
            # pip-compile returns a non-zero status
            return if $CHILD_STATUS.success?
            raise SharedHelpers::HelperSubprocessFailed.new(
              raw_response,
              command
            )
          end

          def write_updated_dependency_files
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, update_dependency_requirement(file))
            end
          end

          def update_dependency_requirement(file)
            return file.content unless file.name.end_with?(".in")
            return file.content unless dependency.version

            old_req = dependency.previous_requirements.
                      find { |r| r[:file] == file.name }
            new_req = dependency.requirements.
                      find { |r| r[:file] == file.name }
            return file.content unless old_req&.fetch(:requirement)

            RequirementReplacer.new(
              content: file.content,
              dependency_name: dependency.name,
              old_requirement: old_req[:requirement],
              new_requirement: new_req[:requirement]
            ).updated_content
          end

          def source_pip_config_file_name
            dependency.requirements.
              map { |r| r[:file] }.
              find { |fn| fn.end_with?(".in") }
          end
        end
      end
    end
  end
end
