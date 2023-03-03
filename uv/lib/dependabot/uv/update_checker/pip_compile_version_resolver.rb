# typed: true
# frozen_string_literal: true

require "open3"
require "dependabot/dependency"
require "dependabot/uv/requirement_parser"
require "dependabot/uv/file_fetcher"
require "dependabot/uv/file_parser"
require "dependabot/uv/file_parser/python_requirement_parser"
require "dependabot/uv/update_checker"
require "dependabot/uv/file_updater/requirement_replacer"
require "dependabot/uv/version"
require "dependabot/shared_helpers"
require "dependabot/uv/language_version_manager"
require "dependabot/uv/native_helpers"
require "dependabot/uv/name_normaliser"
require "dependabot/uv/authed_url_builder"

module Dependabot
  module Uv
    class UpdateChecker
      # This class does version resolution for pip-compile. Its approach is:
      # - Unlock the dependency we're checking in the requirements.in file
      # - Run `pip-compile` and see what the result is
      class PipCompileVersionResolver
        GIT_DEPENDENCY_UNREACHABLE_REGEX = /git clone --filter=blob:none --quiet (?<url>[^\s]+).* /
        GIT_REFERENCE_NOT_FOUND_REGEX = /Did not find branch or tag '(?<tag>[^\n"]+)'/m
        NATIVE_COMPILATION_ERROR =
          "pip._internal.exceptions.InstallationSubprocessError: Getting requirements to build wheel exited with 1"
        # See https://packaging.python.org/en/latest/tutorials/packaging-projects/#configuring-metadata
        PYTHON_PACKAGE_NAME_REGEX = /[A-Za-z0-9_\-]+/
        RESOLUTION_IMPOSSIBLE_ERROR = "ResolutionImpossible"
        ERROR_REGEX = /(?<=ERROR\:\W).*$/
        UV_UNRESOLVABLE_REGEX = / × No solution found when resolving dependencies:[\s\S]*$/

        attr_reader :dependency
        attr_reader :dependency_files
        attr_reader :credentials
        attr_reader :repo_contents_path
        attr_reader :error_handler

        def initialize(dependency:, dependency_files:, credentials:, repo_contents_path:)
          @dependency               = dependency
          @dependency_files         = dependency_files
          @credentials              = credentials
          @repo_contents_path       = repo_contents_path
          @build_isolation = true
          @error_handler = PipCompileErrorHandler.new
        end

        def latest_resolvable_version(requirement: nil)
          @latest_resolvable_version_string ||= {}
          return @latest_resolvable_version_string[requirement] if @latest_resolvable_version_string.key?(requirement)

          version_string =
            fetch_latest_resolvable_version_string(requirement: requirement)

          @latest_resolvable_version_string[requirement] ||=
            version_string.nil? ? nil : Uv::Version.new(version_string)
        end

        def resolvable?(version:)
          @resolvable ||= {}
          return @resolvable[version] if @resolvable.key?(version)

          @resolvable[version] = if latest_resolvable_version(requirement: "==#{version}")
                                   true
                                 else
                                   false
                                 end
        end

        private

        def fetch_latest_resolvable_version_string(requirement:)
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_temporary_dependency_files(updated_req: requirement)
              language_version_manager.install_required_python

              filenames_to_compile.each do |filename|
                return nil unless compile_file(filename)
              end

              # Remove any .python-version file before parsing the reqs
              FileUtils.remove_entry(".python-version", true)

              parse_updated_files
            end
          end
        end

        def compile_file(filename)
          # Shell out to pip-compile.
          # This is slow, as pip-compile needs to do installs.
          options = pip_compile_options(filename)
          options_fingerprint = pip_compile_options_fingerprint(options)

          run_pip_compile_command(
            "pyenv exec uv pip compile -v #{options} -P #{dependency.name} #{filename}",
            fingerprint: "pyenv exec uv pip compile -v #{options_fingerprint} -P <dependency_name> <filename>"
          )

          return true if dependency.top_level?

          # Run pip-compile a second time for transient dependencies
          # to make sure we do not update dependencies that are
          # superfluous. pip-compile does not detect these when
          # updating a specific dependency with the -P option.
          # Running pip-compile a second time will automatically remove
          # superfluous dependencies. Dependabot then marks those with
          # update_not_possible.
          write_original_manifest_files
          run_pip_compile_command(
            "pyenv exec uv pip compile #{options} #{filename}",
            fingerprint: "pyenv exec uv pip compile #{options_fingerprint} <filename>"
          )

          true
        rescue SharedHelpers::HelperSubprocessFailed => e
          retry_count ||= 0
          retry_count += 1
          if compilation_error?(e) && retry_count <= 1
            @build_isolation = false
            retry
          end

          handle_pip_compile_errors(e.message)
        end

        def compilation_error?(error)
          error.message.include?(NATIVE_COMPILATION_ERROR)
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        def handle_pip_compile_errors(message)
          if message.include?("No solution found when resolving dependencies")
            raise DependencyFileNotResolvable, message.scan(UV_UNRESOLVABLE_REGEX).last
          end

          check_original_requirements_resolvable if message.include?(RESOLUTION_IMPOSSIBLE_ERROR)

          # If there's an unsupported constraint, check if it existed
          # previously (and raise if it did)
          check_original_requirements_resolvable if message.include?("UnsupportedConstraint")

          if message.include?(RESOLUTION_IMPOSSIBLE_ERROR) &&
             !message.match?(/#{Regexp.quote(dependency.name)}/i)
            # Sometimes pip-tools gets confused and can't work around
            # sub-dependency incompatibilities. Ignore those cases.
            return nil
          end

          if message.match?(GIT_REFERENCE_NOT_FOUND_REGEX)
            tag = message.match(GIT_REFERENCE_NOT_FOUND_REGEX).named_captures.fetch("tag")
            constraints_section = message.split("Finding the best candidates:").first
            egg_regex = /#{Regexp.escape(tag)}#egg=(#{PYTHON_PACKAGE_NAME_REGEX})/
            name_match = constraints_section.scan(egg_regex)

            # We can determine the name of the package from another part of the logger output if it has a unique tag
            raise GitDependencyReferenceNotFound, name_match.first.first if name_match.length == 1

            raise GitDependencyReferenceNotFound, "(unknown package at #{tag})"
          end

          if message.match?(GIT_DEPENDENCY_UNREACHABLE_REGEX)
            url = message.match(GIT_DEPENDENCY_UNREACHABLE_REGEX)
                         .named_captures.fetch("url")
            raise GitDependenciesNotReachable, url
          end

          raise Dependabot::OutOfDisk if message.end_with?("[Errno 28] No space left on device")

          raise Dependabot::OutOfMemory if message.end_with?("MemoryError")

          error_handler.handle_pipcompile_error(message)

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
                  "pyenv exec uv pip compile #{options} #{filename}",
                  fingerprint: "pyenv exec uv pip compile #{options_fingerprint} <filename>"
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
          SharedHelpers.run_shell_command(command, env: env, fingerprint: fingerprint, stderr_to_stdout: true)
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_pip_compile_errors(e.message)
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
          # TODO: Stop explicitly specifying `allow-unsafe` once it becomes the default:
          # https://github.com/jazzband/pip-tools/issues/989#issuecomment-1661254701
          options += ["--allow-unsafe"]

          if (requirements_file = compiled_file_for_filename(filename))
            options << "--output-file=#{requirements_file.name}"
            options += uv_pip_compile_options_from_compiled_file(requirements_file)
          end

          options.join(" ")
        end

        def pip_compile_index_options
          credentials
            .select { |cred| cred["type"] == "python_index" }
            .map do |cred|
              authed_url = AuthedUrlBuilder.authed_url(credential: cred)

              if cred.replaces_base?
                "--index-url=#{authed_url}"
              else
                "--extra-index-url=#{authed_url}"
              end
            end
        end

        def run_pip_compile_command(command, fingerprint:)
          run_command(
            "pyenv local #{language_version_manager.python_major_minor}",
            fingerprint: "pyenv local <python_major_minor>"
          )

          run_command(command, fingerprint: fingerprint)
        end

        def uv_pip_compile_options_from_compiled_file(requirements_file)
          options = []

          options << "--no-emit-index-url" unless requirements_file.content.include?("index-url http")

          options << "--generate-hashes" if requirements_file.content.include?("--hash=sha")

          options << "--no-annotate" unless requirements_file.content.include?("# via ")

          options << "--pre" if requirements_file.content.include?("--pre")

          options << "--no-strip-extras" if requirements_file.content.include?("--no-strip-extras")

          if requirements_file.content.include?("--no-binary") || requirements_file.content.include?("--only-binary")
            options << "--emit-build-options"
          end

          if (resolver = FileUpdater::CompileFileUpdater::RESOLVER_REGEX.match(requirements_file.content))
            options << "--resolver=#{resolver}"
          end

          options << "--universal" if requirements_file.content.include?("--universal")

          options
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
          File.write(".python-version", language_version_manager.python_major_minor)
        end

        def write_original_manifest_files
          pip_compile_files.each do |file|
            FileUtils.mkdir_p(Pathname.new(file.name).dirname)
            File.write(file.name, file.content)
          end
        end

        def update_req_file(file, updated_req)
          return file.content unless file.name.end_with?(".in")

          req = dependency.requirements.find { |r| r[:file] == file.name }

          return file.content + "\n#{dependency.name} #{updated_req}" unless req&.fetch(:requirement)

          Uv::FileUpdater::RequirementReplacer.new(
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
            dependency.requirements
                      .map { |r| r[:file] }
                      .select { |fn| fn.end_with?(".in") }

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
            compiled_files
            .find { |f| f.content.match?(output_file_regex(filename)) }

          compiled_file ||=
            compiled_files
            .find { |f| f.name == filename.gsub(/\.in$/, ".txt") }

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
          ordered_filenames = T.let([], T::Array[String])

          while (remaining_filenames = filenames - ordered_filenames).any?
            ordered_filenames +=
              remaining_filenames
              .reject do |fn|
                unupdated_reqs = requirement_map[fn] - ordered_filenames
                unupdated_reqs.intersect?(filenames)
              end
          end

          ordered_filenames
        end

        def requirement_map
          child_req_regex = Uv::FileFetcher::CHILD_REQUIREMENT_REGEX
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

          Uv::FileParser.new(
            dependency_files: updated_files,
            source: nil,
            credentials: credentials
          ).parse.find { |d| d.name == dependency.name }&.version
        end

        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        def language_version_manager
          @language_version_manager ||=
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            )
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
    end

    class PipCompileErrorHandler
      SUBPROCESS_ERROR = /subprocess-exited-with-error/

      INSTALLATION_ERROR = /InstallationError/

      INSTALLATION_SUBPROCESS_ERROR = /InstallationSubprocessError/

      HASH_MISMATCH = /HashMismatch/

      def handle_pipcompile_error(error)
        return unless error.match?(SUBPROCESS_ERROR) || error.match?(INSTALLATION_ERROR) ||
                      error.match?(INSTALLATION_SUBPROCESS_ERROR) || error.match?(HASH_MISMATCH)

        raise DependencyFileNotResolvable, "Error resolving dependency"
      end
    end
  end
end
