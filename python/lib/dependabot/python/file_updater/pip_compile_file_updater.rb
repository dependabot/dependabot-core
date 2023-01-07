# frozen_string_literal: true

require "open3"
require "dependabot/dependency"
require "dependabot/python/requirement_parser"
require "dependabot/python/file_fetcher"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/file_updater"
require "dependabot/shared_helpers"
require "dependabot/python/helpers"
require "dependabot/python/native_helpers"
require "dependabot/python/python_versions"
require "dependabot/python/name_normaliser"
require "dependabot/python/authed_url_builder"

module Dependabot
  module Python
    class FileUpdater
      # rubocop:disable Metrics/ClassLength
      class PipCompileFileUpdater
        require_relative "requirement_replacer"
        require_relative "requirement_file_updater"
        require_relative "setup_file_sanitizer"

        UNSAFE_PACKAGES = %w(setuptools distribute pip).freeze
        INCOMPATIBLE_VERSIONS_REGEX = /There are incompatible versions in the resolved dependencies:.*\z/m
        WARNINGS = /\s*# WARNING:.*\Z/m
        UNSAFE_NOTE = /\s*# The following packages are considered to be unsafe.*\Z/m

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
            Helpers.install_required_python(python_version)

            filenames_to_compile.each do |filename|
              # Shell out to pip-compile, generate a new set of requirements.
              # This is slow, as pip-compile needs to do installs.
              options = pip_compile_options(filename)
              options_fingerprint = pip_compile_options_fingerprint(options)

              name_part = "pyenv exec pip-compile " \
                          "#{options} -P " \
                          "#{dependency.name}"
              fingerprint_name_part = "pyenv exec pip-compile " \
                                      "#{options_fingerprint} -P " \
                                      "<dependency_name>"

              version_part = "#{dependency.version} #{filename}"
              fingerprint_version_part = "<dependency_version> <filename>"

              # Don't escape pyenv `dep-name==version` syntax
              run_pip_compile_command(
                "#{SharedHelpers.escape_command(name_part)}==" \
                "#{SharedHelpers.escape_command(version_part)}",
                allow_unsafe_shell_command: true,
                fingerprint: "#{fingerprint_name_part}==#{fingerprint_version_part}"
              )
            end

            # Remove any .python-version file before parsing the reqs
            FileUtils.remove_entry(".python-version", true)

            dependency_files.filter_map do |file|
              next unless file.name.end_with?(".txt")

              updated_content = File.read(file.name)

              updated_content =
                post_process_compiled_file(updated_content, file)
              next if updated_content == file.content

              file.dup.tap { |f| f.content = updated_content }
            end
          end
        end

        def update_manifest_files
          dependency_files.filter_map do |file|
            next unless file.name.end_with?(".in")

            file = file.dup
            updated_content = update_dependency_requirement(file)
            next if updated_content == file.content

            file.content = updated_content
            file
          end
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
          args = args.keys.to_h { |k| [k.to_sym, args[k]] }
          args[:requirements] = new_reqs
          args[:previous_requirements] = old_reqs

          RequirementFileUpdater.new(
            dependencies: [Dependency.new(**args)],
            dependency_files: files,
            credentials: credentials
          ).updated_dependency_files
        end

        def run_command(cmd, env: python_env, allow_unsafe_shell_command: false, fingerprint:)
          start = Time.now
          command = if allow_unsafe_shell_command
                      cmd
                    else
                      SharedHelpers.escape_command(cmd)
                    end
          stdout, process = Open3.capture2e(env, command)
          time_taken = Time.now - start

          return stdout if process.success?

          if stdout.match?(INCOMPATIBLE_VERSIONS_REGEX)
            raise DependencyFileNotResolvable, stdout.match(INCOMPATIBLE_VERSIONS_REGEX)
          end

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

        def run_pip_compile_command(command, allow_unsafe_shell_command: false, fingerprint:)
          run_command(
            "pyenv local #{Helpers.python_major_minor(python_version)}",
            fingerprint: "pyenv local <python_major_minor>"
          )

          run_command(
            command,
            allow_unsafe_shell_command: allow_unsafe_shell_command,
            fingerprint: fingerprint
          )
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

        def write_updated_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, freeze_dependency_requirement(file))
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

        def sanitized_setup_file_content(file)
          @sanitized_setup_file_content ||= {}
          return @sanitized_setup_file_content[file.name] if @sanitized_setup_file_content[file.name]

          @sanitized_setup_file_content[file.name] =
            SetupFileSanitizer.
            new(setup_file: file, setup_cfg: setup_cfg(file)).
            sanitized_content
        end

        def setup_cfg(file)
          dependency_files.find do |f|
            f.name == file.name.sub(/\.py$/, ".cfg")
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

        def post_process_compiled_file(updated_content, file)
          content = replace_header_with_original(updated_content, file.content)
          content = remove_new_warnings(content, file.content)
          content = update_hashes_if_required(content, file.content)
          replace_absolute_file_paths(content, file.content)
        end

        def replace_header_with_original(updated_content, original_content)
          original_header_lines =
            original_content.lines.take_while { |l| l.start_with?("#") }

          updated_content_lines =
            updated_content.lines.drop_while { |l| l.start_with?("#") }

          [*original_header_lines, *updated_content_lines].join
        end

        def replace_absolute_file_paths(updated_content, original_content)
          content = updated_content

          update_count = 0
          original_content.lines.each do |original_line|
            next unless original_line.start_with?("-e")
            next update_count += 1 if updated_content.include?(original_line)

            line_to_update =
              updated_content.lines.
              select { |l| l.start_with?("-e") }.
              at(update_count)
            raise "Mismatch in editable requirements!" unless line_to_update

            content = content.gsub(line_to_update, original_line)
            update_count += 1
          end

          content
        end

        def remove_new_warnings(updated_content, original_content)
          content = updated_content

          content = content.sub(WARNINGS, "\n") if content.match?(WARNINGS) && !original_content.match?(WARNINGS)

          if content.match?(UNSAFE_NOTE) &&
             !original_content.match?(UNSAFE_NOTE)
            content = content.sub(UNSAFE_NOTE, "\n")
          end

          content
        end

        def update_hashes_if_required(updated_content, original_content)
          deps_to_update =
            deps_to_augment_hashes_for(updated_content, original_content)

          updated_content_with_hashes = updated_content
          deps_to_update.each do |mtch|
            updated_string = mtch.to_s.sub(
              RequirementParser::HASHES,
              package_hashes_for(
                name: mtch.named_captures.fetch("name"),
                version: mtch.named_captures.fetch("version"),
                algorithm: mtch.named_captures.fetch("algorithm")
              ).sort.join(hash_separator(mtch.to_s))
            )

            updated_content_with_hashes = updated_content_with_hashes.
                                          gsub(mtch.to_s, updated_string)
          end
          updated_content_with_hashes
        end

        def deps_to_augment_hashes_for(updated_content, original_content)
          regex = /^#{RequirementParser::INSTALL_REQ_WITH_REQUIREMENT}/o

          new_matches = []
          updated_content.scan(regex) { new_matches << Regexp.last_match }

          old_matches = []
          original_content.scan(regex) { old_matches << Regexp.last_match }

          new_deps = []
          changed_hashes_deps = []

          new_matches.each do |mtch|
            nm = mtch.named_captures["name"]
            old_match = old_matches.find { |m| m.named_captures["name"] == nm }

            next new_deps << mtch unless old_match
            next unless old_match.named_captures["hashes"]

            old_count = old_match.named_captures["hashes"].split("--hash").count
            new_count = mtch.named_captures["hashes"].split("--hash").count
            changed_hashes_deps << mtch if new_count < old_count
          end

          return [] if changed_hashes_deps.none?

          [*new_deps, *changed_hashes_deps]
        end

        def package_hashes_for(name:, version:, algorithm:)
          SharedHelpers.run_helper_subprocess(
            command: "pyenv exec python #{NativeHelpers.python_helper_path}",
            function: "get_dependency_hash",
            args: [name, version, algorithm]
          ).map { |h| "--hash=#{algorithm}:#{h['hash']}" }
        end

        def hash_separator(requirement_string)
          hash_regex = RequirementParser::HASH
          return unless requirement_string.match?(hash_regex)

          current_separator =
            requirement_string.
            match(/#{hash_regex}((?<separator>\s*\\?\s*?)#{hash_regex})*/).
            named_captures.fetch("separator")

          default_separator =
            requirement_string.
            match(RequirementParser::HASH).
            pre_match.match(/(?<separator>\s*\\?\s*?)\z/).
            named_captures.fetch("separator")

          current_separator || default_separator
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
          options = ["--build-isolation"]
          options += pip_compile_index_options

          if (requirements_file = compiled_file_for_filename(filename))
            options += pip_compile_options_from_compiled_file(requirements_file)
          end

          options.join(" ")
        end

        def pip_compile_options_from_compiled_file(requirements_file)
          options = ["--output-file=#{requirements_file.name}"]

          options << "--no-emit-index-url" unless requirements_file.content.include?("index-url http")

          options << "--generate-hashes" if requirements_file.content.include?("--hash=sha")

          options << "--allow-unsafe" if includes_unsafe_packages?(requirements_file.content)

          options << "--no-annotate" unless requirements_file.content.include?("# via ")

          options << "--no-header" unless requirements_file.content.include?("autogenerated by pip-c")

          options << "--pre" if requirements_file.content.include?("--pre")

          options << "--strip-extras" if requirements_file.content.include?("--strip-extras")

          options
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

        def includes_unsafe_packages?(content)
          UNSAFE_PACKAGES.any? { |n| content.match?(/^#{Regexp.quote(n)}==/) }
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

        def normalise(name)
          NameNormaliser.normalise(name)
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
