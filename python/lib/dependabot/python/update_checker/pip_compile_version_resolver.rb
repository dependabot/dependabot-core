# frozen_string_literal: true

require "open3"
require "dependabot/python/requirement_parser"
require "dependabot/python/file_fetcher"
require "dependabot/python/file_parser"
require "dependabot/python/update_checker"
require "dependabot/python/file_updater/requirement_replacer"
require "dependabot/python/file_updater/setup_file_sanitizer"
require "dependabot/python/version"
require "dependabot/shared_helpers"
require "dependabot/python/native_helpers"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module Python
    class UpdateChecker
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
                  cmd = "pyenv exec pip-compile --allow-unsafe "\
                        "-P #{dependency.name} #{filename}"
                  run_command(cmd)
                  # Run pip-compile a second time, without an update argument,
                  # to ensure it handles markers correctly
                  run_command(
                    "pyenv exec pip-compile --allow-unsafe #{filename}"
                  )
                end

                # Remove any .python-version file before parsing the reqs
                FileUtils.remove_entry(".python-version", true)

                parse_updated_files
              end
            rescue SharedHelpers::HelperSubprocessFailed => error
              handle_pip_compile_errors(error)
            end
          return unless @latest_resolvable_version_string

          Python::Version.new(@latest_resolvable_version_string)
        end

        def parse_requirements_from_cwd_files
          SharedHelpers.run_helper_subprocess(
            command: "pyenv exec python #{NativeHelpers.python_helper_path}",
            function: "parse_requirements",
            args: [Dir.pwd]
          )
        end

        def handle_pip_compile_errors(error)
          if error.message.include?("Could not find a version")
            check_original_requirements_resolvable
            # If the original requirements are resolvable but we get an
            # incompatibility update after unlocking then it's likely to be
            # due to problems with pip-compile's cascading resolution
            return nil
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
                cmd = "pyenv exec pip-compile --allow-unsafe #{filename}"
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

        # rubocop:disable Metrics/MethodLength
        def run_command(command)
          command = command.dup
          start = Time.now
          stdout, process = Open3.capture2e(command)
          time_taken = start - Time.now

          # Raise an error with the output from the shell session if
          # pip-compile returns a non-zero status
          return if process.success?

          raise SharedHelpers::HelperSubprocessFailed.new(
            message: stdout,
            error_context: {
              command: command,
              time_taken: time_taken,
              process_exit_value: process.to_s
            }
          )
        rescue SharedHelpers::HelperSubprocessFailed => error
          original_error ||= error
          msg = error.message

          relevant_error =
            if error_suggests_bad_python_version?(msg) then original_error
            else error
            end

          raise relevant_error unless error_suggests_bad_python_version?(msg)
          raise relevant_error if File.exist?(".python-version")

          command = "pyenv local 2.7.15 && " + command
          retry
        ensure
          FileUtils.remove_entry(".python-version", true)
        end
        # rubocop:enable Metrics/MethodLength

        def error_suggests_bad_python_version?(message)
          return true if message.include?("not find a version that satisfies")
          return true if message.include?("No matching distribution found")

          message.include?('Command "python setup.py egg_info" failed')
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
            Python::FileUpdater::SetupFileSanitizer.
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

          Python::FileUpdater::RequirementReplacer.new(
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
          unless Python::Version.correct?(latest_allowable_version)
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
              compiled_file_includes_dependency?(compiled_file)
            end

          filenames = [*files_from_reqs, *files_from_compiled_files].uniq

          order_filenames_for_compilation(filenames)
        end

        def compiled_file_includes_dependency?(compiled_file)
          return false unless compiled_file

          regex = RequirementParser::INSTALL_REQ_WITH_REQUIREMENT

          matches = []
          compiled_file.content.scan(regex) { matches << Regexp.last_match }
          matches.any? { |m| normalise(m[:name]) == dependency.name }
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
          child_req_regex = Python::FileFetcher::CHILD_REQUIREMENT_REGEX
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

        def parse_updated_files
          updated_files =
            dependency_files.map do |file|
              next file if file.name == ".python-version"

              updated_file = file.dup
              updated_file.content = File.read(file.name)
              updated_file
            end

          Python::FileParser.new(
            dependency_files: updated_files,
            source: nil,
            credentials: credentials
          ).parse.find { |d| d.name == dependency.name }&.version
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
# rubocop:enable Metrics/ClassLength
