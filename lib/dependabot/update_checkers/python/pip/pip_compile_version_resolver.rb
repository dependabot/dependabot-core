# frozen_string_literal: true

require "dependabot/file_fetchers/python/pip"
require "dependabot/update_checkers/python/pip"
require "dependabot/file_updaters/python/pip/requirement_replacer"
require "dependabot/file_updaters/python/pip/setup_file_sanitizer"
require "dependabot/utils/python/version"
require "dependabot/shared_helpers"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module UpdateCheckers
    module Python
      class Pip
        # This class does version resolution for pip-compile. Its approach is:
        # - Unlock the dependency we're checking in the requirements.in file
        # - Run `pip-compile` and see what the result is
        class PipCompileVersionResolver
          VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/.freeze

          attr_reader :dependency, :dependency_files, :credentials

          def initialize(dependency:, dependency_files:, credentials:,
                         unlock_requirement:, latest_allowable_version:)
            @dependency               = dependency
            @dependency_files         = dependency_files
            @credentials              = credentials
            @latest_allowable_version = latest_allowable_version
            @unlock_requirement       = unlock_requirement
          end

          def latest_resolvable_version
            return @latest_resolvable_version if @resolution_already_attempted

            @resolution_already_attempted = true
            @latest_resolvable_version ||= fetch_latest_resolvable_version
          end

          private

          attr_reader :latest_allowable_version

          def unlock_requirement?
            @unlock_requirement
          end

          def fetch_latest_resolvable_version
            @latest_resolvable_version_string ||=
              SharedHelpers.in_a_temporary_directory do
                SharedHelpers.with_git_configured(credentials: credentials) do
                  write_temporary_dependency_files

                  filenames_to_compile.each do |filename|
                    # Shell out to pip-compile.
                    # This is slow, as pip-compile needs to do installs.
                    cmd = "pyenv exec pip-compile -P #{dependency.name} "\
                          "#{filename}"
                    run_command(cmd)
                  end

                  # Remove the created package details (so they aren't parsed)
                  FileUtils.rm_rf("sanitized_package.egg-info")

                  # Remove any .python-version file before parsing the reqs
                  FileUtils.remove_entry(".python-version", true)

                  parse_requirements_from_cwd_files.
                    select { |dep| normalise(dep["name"]) == dependency.name }.
                    find { |dep| dep["file"] == source_compiled_file_name }&.
                    fetch("version")
                end
              rescue SharedHelpers::HelperSubprocessFailed => error
                handle_pip_compile_errors(error)
              end
            return unless @latest_resolvable_version_string

            Utils::Python::Version.new(@latest_resolvable_version_string)
          end

          def parse_requirements_from_cwd_files
            SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python #{python_helper_path}",
              function: "parse_requirements",
              args: [Dir.pwd]
            )
          end

          def handle_pip_compile_errors(error)
            if error.message.include?("Could not find a version")
              check_original_requirements_resolvable
            end

            if error.message.include?('Command "python setup.py egg_info') &&
               error.message.include?(dependency.name)
              # The latest version of the dependency we're updating is borked
              # (because it has an unevaluatable setup.py). Skip the update.
              return nil
            end

            if error.message.include?("Could not find a version ") &&
               !error.message.include?(dependency.name)
              # Sometimes pip-tools gets confused and can't work around
              # sub-dependency incompatibilities. Ignore those cases.
              return nil
            end

            raise
          end

          # Needed because pip-compile's resolver isn't perfect.
          # Note: We raise errors from this method, rather than returning a
          # boolean, so that all deps for this repo will raise identical
          # errors when failing to update
          def check_original_requirements_resolvable
            SharedHelpers.in_a_temporary_directory do
              SharedHelpers.with_git_configured(credentials: credentials) do
                write_temporary_dependency_files(unlock_requirement: false)

                filenames_to_compile.each do |filename|
                  cmd = "pyenv exec pip-compile #{filename}"
                  run_command(cmd)
                end

                true
              rescue SharedHelpers::HelperSubprocessFailed => error
                raise unless error.message.include?("Could not find a version")

                msg = clean_error_message(error.message)
                raise if msg.empty?

                raise DependencyFileNotResolvable, msg
              end
            end
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
            original_error ||= error
            raise unless error.message.include?("InstallationError") ||
                         error.message.include?("Could not find a version")
            raise original_error if File.exist?(".python-version")

            command = "pyenv local 2.7.15 && " + command
            retry
          ensure
            FileUtils.remove_entry(".python-version", true)
          end

          def write_temporary_dependency_files(unlock_requirement: true)
            dependency_files.each do |file|
              next if file.name == ".python-version"

              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(
                path,
                unlock_requirement ? unlock_dependency(file) : file.content
              )
            end

            setup_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, sanitized_setup_file_content(file))
            end

            setup_cfg_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, "[metadata]\nname = sanitized-package\n")
            end
          end

          def sanitized_setup_file_content(file)
            @sanitized_setup_file_content ||= {}
            if @sanitized_setup_file_content[file.name]
              return @sanitized_setup_file_content[file.name]
            end

            @sanitized_setup_file_content[file.name] =
              FileUpdaters::Python::Pip::SetupFileSanitizer.
              new(setup_file: file, setup_cfg: setup_cfg(file)).
              sanitized_content
          end

          def setup_cfg(file)
            dependency_files.find do |f|
              f.name == file.name.sub(/\.py$/, ".cfg")
            end
          end

          def unlock_dependency(file)
            return file.content unless file.name.end_with?(".in")
            return file.content unless dependency.version
            return file.content unless unlock_requirement?

            req = dependency.requirements.find { |r| r[:file] == file.name }
            return file.content unless req&.fetch(:requirement)

            FileUpdaters::Python::Pip::RequirementReplacer.new(
              content: file.content,
              dependency_name: dependency.name,
              old_requirement: req[:requirement],
              new_requirement: updated_version_requirement_string
            ).updated_content
          end

          def updated_version_requirement_string
            lower_bound_req = updated_version_req_lower_bound

            # Add the latest_allowable_version as an upper bound. This means
            # ignore conditions are considered when checking for the latest
            # resolvable version.
            #
            # NOTE: This isn't perfect. If v2.x is ignored and v3 is out but
            # unresolvable then the `latest_allowable_version` will be v3, and
            # we won't be ignoring v2.x releases like we should be.
            return lower_bound_req if latest_allowable_version.nil?
            unless Utils::Python::Version.correct?(latest_allowable_version)
              return lower_bound_req
            end

            lower_bound_req + ", <= #{latest_allowable_version}"
          end

          def updated_version_req_lower_bound
            if dependency.version
              ">= #{dependency.version}"
            else
              version_for_requirement =
                dependency.requirements.map { |r| r[:requirement] }.compact.
                reject { |req_string| req_string.start_with?("<") }.
                select { |req_string| req_string.match?(VERSION_REGEX) }.
                map { |req_string| req_string.match(VERSION_REGEX) }.
                select { |version| Gem::Version.correct?(version) }.
                max_by { |version| Gem::Version.new(version) }

              ">= #{version_for_requirement || 0}"
            end
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

          def source_compiled_file_name
            source_pip_config_file_name.sub(/\.in$/, ".txt")
          end

          def python_helper_path
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/python/run.py")
          end

          # See https://www.python.org/dev/peps/pep-0503/#normalized-names
          def normalise(name)
            name.downcase.gsub(/[-_.]+/, "-")
          end

          def clean_error_message(message)
            # Redact any URLs, as they may include credentials
            message.gsub(/http.*?(?=\s)/, "<redacted>")
          end

          def filenames_to_compile
            files_from_reqs =
              dependency.requirements.
              map { |r| r[:file] }.
              select { |fn| fn.end_with?(".in") }

            files_from_compiled_files =
              pip_compile_files.map(&:name).select do |fn|
                compiled_file = dependency_files.
                                find { |f| f.name == fn.gsub(/\.in$/, ".txt") }
                compiled_file&.content&.include?(dependency.name)
              end

            filenames = [*files_from_reqs, *files_from_compiled_files].uniq

            order_filenames_for_compilation(filenames)
          end

          # If the files we need to update require one another then we need to
          # update them in the right order
          def order_filenames_for_compilation(filenames)
            ordered_filenames = []

            while (remaining_filenames = filenames - ordered_filenames).any?
              ordered_filenames +=
                remaining_filenames.
                select do |fn|
                  unupdated_reqs = requirement_map[fn] - ordered_filenames
                  (unupdated_reqs & filenames).empty?
                end
            end

            ordered_filenames
          end

          def requirement_map
            child_req_regex = FileFetchers::Python::Pip::CHILD_REQUIREMENT_REGEX
            @requirement_map ||=
              pip_compile_files.each_with_object({}) do |file, req_map|
                paths = file.content.scan(child_req_regex).flatten
                current_dir = File.dirname(file.name)

                req_map[file.name] =
                  paths.map do |path|
                    path = File.join(current_dir, path) if current_dir != "."
                    path = Pathname.new(path).cleanpath.to_path
                    path = path.gsub(/\.txt$/, ".in")
                    next if path == file.name

                    path
                  end.uniq.compact
              end
          end

          def setup_files
            dependency_files.select { |f| f.name.end_with?("setup.py") }
          end

          def pip_compile_files
            dependency_files.select { |f| f.name.end_with?(".in") }
          end

          def setup_cfg_files
            dependency_files.select { |f| f.name.end_with?("setup.cfg") }
          end
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
