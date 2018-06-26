# frozen_string_literal: true

require "dependabot/file_updaters/python/pip"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Python
      class Pip
        class PipCompileFileUpdater
          require_relative "requirement_replacer"
          require_relative "requirement_file_updater"

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
            updated_compiled_files = compile_new_requirement_files
            updated_manifest_files = update_manifest_files

            updated_files = updated_compiled_files + updated_manifest_files
            updated_uncompiled_files = update_uncompiled_files(updated_files)

            [
              *updated_manifest_files,
              *updated_compiled_files,
              *updated_uncompiled_files
            ]
          end

          def compile_new_requirement_files
            SharedHelpers.in_a_temporary_directory do
              write_updated_dependency_files

              # Shell out to pip-compile, generate a new set of requirements.
              # This is slow, as pip-compile needs to do installs.
              cmd = "pyenv exec pip-compile #{pip_compile_options} "\
                    "-P #{dependency.name} #{source_pip_config_file_name}"
              run_command(cmd)

              dependency_files.map do |file|
                next unless file.name.end_with?(".txt")
                updated_content = File.read(file.name)

                updated_content =
                  replace_header_with_original(updated_content, file.content)
                next if updated_content == file.content

                file = file.dup
                file.content = updated_content
                file
              end.compact
            end
          end

          def update_manifest_files
            dependency_files.map do |file|
              next unless file.name.end_with?(".in")
              file = file.dup
              updated_content = update_dependency_requirement(file)
              next if updated_content == file.content
              file.content = updated_content
              file
            end.compact
          end

          def update_uncompiled_files(updated_files)
            updated_filenames = updated_files.map(&:name)
            old_reqs = dependency.previous_requirements.
                       reject { |r| updated_filenames.include?(r[:file]) }
            new_reqs = dependency.requirements.
                       reject { |r| updated_filenames.include?(r[:file]) }

            return [] if new_reqs.none?

            files = dependency_files.
                    reject { |file| updated_filenames.include?(file.name) }

            args = dependency.to_h
            args = Hash[args.keys.map { |k| [k.to_sym, args[k]] }]
            args[:requirements] = new_reqs
            args[:previous_requirements] = old_reqs

            RequirementFileUpdater.new(
              dependencies: [Dependency.new(**args)],
              dependency_files: files,
              credentials: credentials
            ).updated_dependency_files
          end

          def run_command(command)
            command = command.dup
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
          rescue SharedHelpers::HelperSubprocessFailed => error
            raise unless error.message.include?("InstallationError")
            raise if command.start_with?("pyenv local 2.7.15 &&")
            command = "pyenv local 2.7.15 && " +
                      command +
                      " && pyenv local --unset"
            retry
          end

          def write_updated_dependency_files
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, freeze_dependency_requirement(file))
            end
          end

          def freeze_dependency_requirement(file)
            return file.content unless file.name.end_with?(".in")

            old_req = dependency.previous_requirements.
                      find { |r| r[:file] == file.name }

            return file.content unless old_req
            return file.content if old_req == "==#{dependency.version}"

            RequirementReplacer.new(
              content: file.content,
              dependency_name: dependency.name,
              old_requirement: old_req[:requirement],
              new_requirement: "==#{dependency.version}"
            ).updated_content
          end

          def update_dependency_requirement(file)
            return file.content unless file.name.end_with?(".in")

            old_req = dependency.previous_requirements.
                      find { |r| r[:file] == file.name }
            new_req = dependency.requirements.
                      find { |r| r[:file] == file.name }
            return file.content unless old_req&.fetch(:requirement)
            return file.content if old_req == new_req

            RequirementReplacer.new(
              content: file.content,
              dependency_name: dependency.name,
              old_requirement: old_req[:requirement],
              new_requirement: new_req[:requirement]
            ).updated_content
          end

          def replace_header_with_original(updated_content, original_content)
            original_header_lines =
              original_content.lines.take_while { |l| l.start_with?("#") }

            updated_content_lines =
              updated_content.lines.drop_while { |l| l.start_with?("#") }

            [*original_header_lines, *updated_content_lines].join
          end

          def source_pip_config_file_name
            file_from_reqs =
              dependency.requirements.
              map { |r| r[:file] }.
              find { |fn| fn.end_with?(".in") }

            return file_from_reqs if file_from_reqs

            pip_compile_filenames =
              dependency_files.
              select { |f| f.name.end_with?(".in") }.
              map(&:name)

            pip_compile_filenames.find do |fn|
              req_file = dependency_files.
                         find { |f| f.name == fn.gsub(/\.in$/, ".txt") }
              req_file&.content&.include?(dependency.name)
            end
          end

          def pip_compile_options
            current_requirements_file_name =
              source_pip_config_file_name.sub(/\.in$/, ".txt")

            requirements_file =
              dependency_files.
              find { |f| f.name == current_requirements_file_name }

            return unless requirements_file

            options = ""

            if requirements_file.content.include?("--hash=sha")
              options += " --generate-hashes"
            end

            unless requirements_file.content.include?("# via ")
              options += " --no-annotate"
            end

            unless requirements_file.content.include?("autogenerated by pip-c")
              options += " --no-header"
            end

            options.strip
          end
        end
      end
    end
  end
end
