# frozen_string_literal: true

require "open3"
require "dependabot/dependency"
require "dependabot/python/requirement_parser"
require "dependabot/python/file_fetcher"
require "dependabot/python/file_parser"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/update_checker"
require "dependabot/python/file_updater/requirement_replacer"
require "dependabot/python/file_updater/setup_file_sanitizer"
require "dependabot/python/version"
require "dependabot/shared_helpers"
require "dependabot/python/helpers"
require "dependabot/python/native_helpers"
require "dependabot/python/python_versions"
require "dependabot/python/name_normaliser"
require "dependabot/python/authed_url_builder"

module Dependabot
  module Python
    class UpdateChecker
      # This class does version resolution for pip-compile. Its approach is:
      # - Unlock the dependency we're checking in the requirements.in file
      # - Run `pip-compile` and see what the result is
      # rubocop:disable Metrics/ClassLength
      class PipCompileVersionResolver
        GIT_DEPENDENCY_UNREACHABLE_REGEX = /git clone --filter=blob:none --quiet (?<url>[^\s]+).* /
        GIT_REFERENCE_NOT_FOUND_REGEX = /Did not find branch or tag '(?<tag>[^\n"]+)'/m
        NATIVE_COMPILATION_ERROR =
          "pip._internal.exceptions.InstallationSubprocessError: Command errored out with exit status 1:"
        # See https://packaging.python.org/en/latest/tutorials/packaging-projects/#configuring-metadata
        PYTHON_PACKAGE_NAME_REGEX = /[A-Za-z0-9_\-]+/
        RESOLUTION_IMPOSSIBLE_ERROR = "ResolutionImpossible"
        ERROR_REGEX = /(?<=ERROR\:\W).*$/

        attr_reader :dependency, :dependency_files, :credentials

        def initialize(dependency:, dependency_files:, credentials:)
          @dependency               = dependency
          @dependency_files         = dependency_files
          @credentials              = credentials
          @build_isolation = true
        end

        def latest_resolvable_version(requirement: nil)
          version_string =
            fetch_latest_resolvable_version_string(requirement: requirement)

          version_string.nil? ? nil : Python::Version.new(version_string)
        end

        def resolvable?(version:)
          @resolvable ||= {}
          return @resolvable[version] if @resolvable.key?(version)

          @resolvable[version] = if fetch_latest_resolvable_version_string(requirement: "==#{version}")
                                   true
                                 else
                                   false
                                 end
        end

        private

        def fetch_latest_resolvable_version_string(requirement:)
          @latest_resolvable_version_string ||= {}
          return @latest_resolvable_version_string[requirement] if @latest_resolvable_version_string.key?(requirement)

          @latest_resolvable_version_string[requirement] ||=
            SharedHelpers.in_a_temporary_directory do
              SharedHelpers.with_git_configured(credentials: credentials) do
                write_temporary_dependency_files(updated_req: requirement)
                Helpers.install_required_python(python_version)

                filenames_to_compile.each do |filename|
                  # Shell out to pip-compile.
                  # This is slow, as pip-compile needs to do installs.
                  options = pip_compile_options(filename)
                  options_fingerprint = pip_compile_options_fingerprint(options)

                  run_pip_compile_command(
                    "pyenv exec pip-compile -v #{options} -P #{dependency.name} #{filename}",
                    fingerprint: "pyenv exec pip-compile -v #{options_fingerprint} -P <dependency_name> <filename>"
                  )

                  next if dependency.top_level?

                  # Run pip-compile a second time for transient dependencies
                  # to make sure we do not update dependencies that are
                  # superfluous. pip-compile does not detect these when
                  # updating a specific dependency with the -P option.
                  # Running pip-compile a second time will automatically remove
                  # superfluous dependencies. Dependabot then marks those with
                  # update_not_possible.
                  write_original_manifest_files
                  run_pip_compile_command(
                    "pyenv exec pip-compile #{options} #{filename}",
                    fingerprint: "pyenv exec pip-compile #{options_fingerprint} <filename>"
                  )
                end

                # Remove any .python-version file before parsing the reqs
                FileUtils.remove_entry(".python-version", true)

                parse_updated_files
              end
            rescue SharedHelpers::HelperSubprocessFailed => e
              retry_count ||= 0
              retry_count += 1
              if compilation_error?(e) && retry_count <= 1
                @build_isolation = false
                retry
              end

              handle_pip_compile_errors(e)
            end
        end

        def compilation_error?(error)
          error.message.include?(NATIVE_COMPILATION_ERROR)
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        def handle_pip_compile_errors(error)
          if error.message.include?(RESOLUTION_IMPOSSIBLE_ERROR)
            check_original_requirements_resolvable
            # If the original requirements are resolvable but we get an
            # incompatibility error after unlocking then it's likely to be
            # due to problems with pip-compile's cascading resolution
            return nil
          end

          if error.message.include?("UnsupportedConstraint")
            # If there's an unsupported constraint, check if it existed
            # previously (and raise if it did)
            check_original_requirements_resolvable
          end

          if (error.message.include?('Command "python setup.py egg_info') ||
              error.message.include?(
                "exit status 1: python setup.py egg_info"
              )) &&
             check_original_requirements_resolvable
            # The latest version of the dependency we're updating is borked
            # (because it has an unevaluatable setup.py). Skip the update.
            return
          end

          if error.message.include?(RESOLUTION_IMPOSSIBLE_ERROR) &&
             !error.message.match?(/#{Regexp.quote(dependency.name)}/i)
            # Sometimes pip-tools gets confused and can't work around
            # sub-dependency incompatibilities. Ignore those cases.
            return nil
          end

          if error.message.match?(GIT_REFERENCE_NOT_FOUND_REGEX)
            tag = error.message.match(GIT_REFERENCE_NOT_FOUND_REGEX).named_captures.fetch("tag")
            constraints_section = error.message.split("Finding the best candidates:").first
            egg_regex = /#{Regexp.escape(tag)}#egg=(#{PYTHON_PACKAGE_NAME_REGEX})/
            name_match = constraints_section.scan(egg_regex)

            # We can determine the name of the package from another part of the logger output if it has a unique tag
            raise GitDependencyReferenceNotFound, name_match.first.first if name_match.length == 1

            raise GitDependencyReferenceNotFound, "(unknown package at #{tag})"
          end

          if error.message.match?(GIT_DEPENDENCY_UNREACHABLE_REGEX)
            url = error.message.match(GIT_DEPENDENCY_UNREACHABLE_REGEX).
                  named_captures.fetch("url")
            raise GitDependenciesNotReachable, url
          end

          raise
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity

        # Needed because pip-compile's resolver isn't perfect.
        # Note: We raise errors from this method, rather than returning a
        # boolean, so that all deps for this repo will raise identical
        # errors when failing to update
        def check_original_requirements_resolvable
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_temporary_dependency_files(update_requirement: false)

              filenames_to_compile.each do |filename|
                options = pip_compile_options(filename)
                options_fingerprint = pip_compile_options_fingerprint(options)

                run_pip_compile_command(
                  "pyenv exec pip-compile #{options} #{filename}",
                  fingerprint: "pyenv exec pip-compile #{options_fingerprint} <filename>"
                )
              end

              true
            rescue SharedHelpers::HelperSubprocessFailed => e
              # Pick the error message that includes resolvability errors, this might be the cause from
              # handle_pip_compile_errors (it's unclear if we should always pick the cause here)
              error_message = [e.message, e.cause&.message].compact.find do |msg|
                msg.include?(RESOLUTION_IMPOSSIBLE_ERROR)
              end

              cleaned_message = clean_error_message(error_message || "")
              raise if cleaned_message.empty?

              raise DependencyFileNotResolvable, cleaned_message
            end
          end
        end

        def run_command(command, env: python_env, fingerprint:)
          start = Time.now
          command = SharedHelpers.escape_command(command)
          stdout, process = Open3.capture2e(env, command)
          time_taken = Time.now - start

          return stdout if process.success?

          raise SharedHelpers::HelperSubprocessFailed.new(
            message: stdout,
            error_context: {
              command: command,
              fingerprint: fingerprint,
              time_taken: time_taken,
              process_exit_value: process.to_s
            }
          )
        end

        def new_resolver_supported?
          python_version >= Python::Version.new("3.7")
        end

        def pip_compile_options_fingerprint(options)
          options.sub(
            /--output-file=\S+/, "--output-file=<output_file>"
          ).sub(
            /--index-url=\S+/, "--index-url=<index_url>"
          ).sub(
            /--extra-index-url=\S+/, "--extra-index-url=<extra_index_url>"
          )
        end

        def pip_compile_options(filename)
          options = @build_isolation ? ["--build-isolation"] : ["--no-build-isolation"]
          options += pip_compile_index_options
          options += ["--allow-unsafe"]
          options += ["--resolver backtracking"] if new_resolver_supported?

          if (requirements_file = compiled_file_for_filename(filename))
            options << "--output-file=#{requirements_file.name}"
          end

          options.join(" ")
        end

        def pip_compile_index_options
          credentials.
            select { |cred| cred["type"] == "python_index" }.
            map do |cred|
              authed_url = AuthedUrlBuilder.authed_url(credential: cred)

              if cred["replaces-base"]
                "--index-url=#{authed_url}"
              else
                "--extra-index-url=#{authed_url}"
              end
            end
        end

        def run_pip_compile_command(command, fingerprint:)
          run_command(
            "pyenv local #{Helpers.python_major_minor(python_version)}",
            fingerprint: "pyenv local <python_major_minor>"
          )

          run_command(command, fingerprint: fingerprint)
        end

        def python_env
          env = {}

          # Handle Apache Airflow 1.10.x installs
          if dependency_files.any? { |f| f.content.include?("apache-airflow") }
            if dependency_files.any? { |f| f.content.include?("unidecode") }
              env["AIRFLOW_GPL_UNIDECODE"] = "yes"
            else
              env["SLUGIFY_USES_TEXT_UNIDECODE"] = "yes"
            end
          end

          env
        end

        def error_certainly_bad_python_version?(message)
          return true if message.include?("UnsupportedPythonVersion")

          unless message.include?('"python setup.py egg_info" failed') ||
                 message.include?("exit status 1: python setup.py egg_info")
            return false
          end

          message.include?("SyntaxError")
        end

        def write_temporary_dependency_files(updated_req: nil,
                                             update_requirement: true)
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            updated_content =
              if update_requirement then update_req_file(file, updated_req)
              else
                file.content
              end
            File.write(path, updated_content)
          end

          # Overwrite the .python-version with updated content
          File.write(".python-version", Helpers.python_major_minor(python_version))

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

        def write_original_manifest_files
          pip_compile_files.each do |file|
            FileUtils.mkdir_p(Pathname.new(file.name).dirname)
            File.write(file.name, file.content)
          end
        end

        def sanitized_setup_file_content(file)
          @sanitized_setup_file_content ||= {}
          return @sanitized_setup_file_content[file.name] if @sanitized_setup_file_content[file.name]

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

        def update_req_file(file, updated_req)
          return file.content unless file.name.end_with?(".in")

          req = dependency.requirements.find { |r| r[:file] == file.name }

          return file.content + "\n#{dependency.name} #{updated_req}" unless req&.fetch(:requirement)

          Python::FileUpdater::RequirementReplacer.new(
            content: file.content,
            dependency_name: dependency.name,
            old_requirement: req[:requirement],
            new_requirement: updated_req
          ).updated_content
        end

        def normalise(name)
          NameNormaliser.normalise(name)
        end

        def clean_error_message(message)
          message.scan(ERROR_REGEX).last
        end

        def filenames_to_compile
          files_from_reqs =
            dependency.requirements.
            map { |r| r[:file] }.
            select { |fn| fn.end_with?(".in") }

          files_from_compiled_files =
            pip_compile_files.map(&:name).select do |fn|
              compiled_file = compiled_file_for_filename(fn)
              compiled_file_includes_dependency?(compiled_file)
            end

          filenames = [*files_from_reqs, *files_from_compiled_files].uniq

          order_filenames_for_compilation(filenames)
        end

        def compiled_file_for_filename(filename)
          compiled_file =
            compiled_files.
            find { |f| f.content.match?(output_file_regex(filename)) }

          compiled_file ||=
            compiled_files.
            find { |f| f.name == filename.gsub(/\.in$/, ".txt") }

          compiled_file
        end

        def output_file_regex(filename)
          "--output-file[=\s]+.*\s#{Regexp.escape(filename)}\s*$"
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
              reject do |fn|
                unupdated_reqs = requirement_map[fn] - ordered_filenames
                unupdated_reqs.intersect?(filenames)
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

        def python_version
          @python_version ||=
            user_specified_python_version ||
            python_version_matching_imputed_requirements ||
            PythonVersions::PRE_INSTALLED_PYTHON_VERSIONS.first
        end

        def user_specified_python_version
          return unless python_requirement_parser.user_specified_requirements.any?

          user_specified_requirements =
            python_requirement_parser.user_specified_requirements.
            map { |r| Python::Requirement.requirements_array(r) }
          python_version_matching(user_specified_requirements)
        end

        def python_version_matching_imputed_requirements
          compiled_file_python_requirement_markers =
            python_requirement_parser.imputed_requirements.map do |r|
              Dependabot::Python::Requirement.new(r)
            end
          python_version_matching(compiled_file_python_requirement_markers)
        end

        def python_version_matching(requirements)
          PythonVersions::SUPPORTED_VERSIONS_TO_ITERATE.find do |version_string|
            version = Python::Version.new(version_string)
            requirements.all? do |req|
              next req.any? { |r| r.satisfied_by?(version) } if req.is_a?(Array)

              req.satisfied_by?(version)
            end
          end
        end

        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        def pre_installed_python?(version)
          PythonVersions::PRE_INSTALLED_PYTHON_VERSIONS.include?(version)
        end

        def setup_files
          dependency_files.select { |f| f.name.end_with?("setup.py") }
        end

        def pip_compile_files
          dependency_files.select { |f| f.name.end_with?(".in") }
        end

        def compiled_files
          dependency_files.select { |f| f.name.end_with?(".txt") }
        end

        def setup_cfg_files
          dependency_files.select { |f| f.name.end_with?("setup.cfg") }
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
