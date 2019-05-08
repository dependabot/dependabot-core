# frozen_string_literal: true

require "open3"
require "dependabot/python/requirement_parser"
require "dependabot/python/file_fetcher"
require "dependabot/python/file_updater"
require "dependabot/shared_helpers"
require "dependabot/python/native_helpers"
require "dependabot/python/python_versions"

module Dependabot
  module Python
    class FileUpdater
      # rubocop:disable Metrics/ClassLength
      class PipCompileFileUpdater
        require_relative "requirement_replacer"
        require_relative "requirement_file_updater"
        require_relative "setup_file_sanitizer"

        UNSAFE_PACKAGES = %w(setuptools distribute pip).freeze

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

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/BlockLength
        def compile_new_requirement_files
          SharedHelpers.in_a_temporary_directory do
            write_updated_dependency_files
            install_required_python

            filenames_to_compile.each do |filename|
              # Shell out to pip-compile, generate a new set of requirements.
              # This is slow, as pip-compile needs to do installs.
              name_part = "pyenv exec pip-compile "\
                          "#{pip_compile_options(filename)} -P "\
                          "#{dependency.name}"
              version_part = "#{dependency.version} #{filename}"
              # Don't escape pyenv `dep-name==version` syntax
              run_pip_compile_command(
                "#{SharedHelpers.escape_command(name_part)}=="\
                "#{SharedHelpers.escape_command(version_part)}",
                escape_command_str: false
              )
              # Run pip-compile a second time, without an update argument, to
              # ensure it resets the right comments.
              run_pip_compile_command(
                "pyenv exec pip-compile #{pip_compile_options(filename)} "\
                "#{filename}"
              )

              unredact_git_credentials_in_compiled_file(filename)
            end

            # Remove any .python-version file before parsing the reqs
            FileUtils.remove_entry(".python-version", true)

            dependency_files.map do |file|
              next unless file.name.end_with?(".txt")

              updated_content = File.read(file.name)

              updated_content =
                post_process_compiled_file(updated_content, file)
              next if updated_content == file.content

              file.dup.tap { |f| f.content = updated_content }
            end.compact
          end
        end
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/BlockLength

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

        def run_command(cmd, env: python_env, escape_command_str: true)
          start = Time.now
          command = escape_command_str ? SharedHelpers.escape_command(cmd) : cmd
          stdout, process = Open3.capture2e(env, command)
          time_taken = Time.now - start

          return stdout if process.success?

          raise SharedHelpers::HelperSubprocessFailed.new(
            message: stdout,
            error_context: {
              command: command,
              time_taken: time_taken,
              process_exit_value: process.to_s
            }
          )
        end

        def run_pip_compile_command(command, escape_command_str: true)
          run_command("pyenv local #{python_version}")
          run_command(command, escape_command_str: escape_command_str)
        rescue SharedHelpers::HelperSubprocessFailed => e
          original_error ||= e
          msg = e.message

          relevant_error =
            if error_suggests_bad_python_version?(msg) then original_error
            else e
            end

          raise relevant_error unless error_suggests_bad_python_version?(msg)
          raise relevant_error if user_specified_python_version
          raise relevant_error if python_version == "2.7.16"

          @python_version = "2.7.16"
          retry
        ensure
          @python_version = nil
          FileUtils.remove_entry(".python-version", true)
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

        def error_suggests_bad_python_version?(message)
          return true if message.include?("not find a version that satisfies")

          message.include?('Command "python setup.py egg_info" failed')
        end

        def write_updated_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, freeze_dependency_requirement(file))
          end

          # Overwrite the .python-version with updated content
          File.write(".python-version", python_version)

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

        def install_required_python
          if run_command("pyenv versions").include?("#{python_version}\n")
            return
          end

          run_command("pyenv install -s #{python_version}")
          run_command("pyenv exec pip install -r "\
                      "#{NativeHelpers.python_requirements_path}")
        end

        def sanitized_setup_file_content(file)
          @sanitized_setup_file_content ||= {}
          if @sanitized_setup_file_content[file.name]
            return @sanitized_setup_file_content[file.name]
          end

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

        # Pip redacts git credentials in the compiled pip-tools file. We don't
        # want that, as it makes the compiled files unusable. (This is kind of
        # a pip-tools bug.)
        def unredact_git_credentials_in_compiled_file(filename)
          compiled_name = filename.gsub(/\.in$/, ".txt")
          original_content = dependency_files.
                             find { |f| f.name == compiled_name }&.content ||
                             dependency_files.
                             find { |f| f.name == filename }.content

          updated_content = File.read(compiled_name)
          new_content = updated_content

          update_count = 0
          original_content.lines.each do |original_line|
            next unless original_line.match?(/^(-e )?git+/)
            next unless original_line.match?(%r{(?<=:)[^/].*?(?=@)})
            next update_count += 1 if updated_content.include?(original_line)

            line_to_update =
              updated_content.lines.
              select { |l| l.match?(/^(-e )?git+/) && l.include?(":****@") }.
              at(update_count)
            raise "Mismatch in editable requirements!" unless line_to_update

            auth = original_line.match(%r{(?<=:)[^/].*?(?=@)}).to_s
            new_content =
              new_content.
              gsub(line_to_update, line_to_update.gsub(":****@", ":#{auth}@"))
            update_count += 1
          end

          File.write(compiled_name, new_content)
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
          regex = RequirementParser::INSTALL_REQ_WITH_REQUIREMENT

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

        def pip_compile_options(filename)
          current_requirements_file_name = filename.sub(/\.in$/, ".txt")

          requirements_file =
            dependency_files.
            find { |f| f.name == current_requirements_file_name }

          return unless requirements_file

          options = ["--build-isolation"]

          if requirements_file.content.include?("--hash=sha")
            options << "--generate-hashes"
          end

          if includes_unsafe_packages?(requirements_file.content)
            options << "--allow-unsafe"
          end

          unless requirements_file.content.include?("# via ")
            options << "--no-annotate"
          end

          unless requirements_file.content.include?("autogenerated by pip-c")
            options << "--no-header"
          end

          options.join(" ")
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

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalise(name)
          name.downcase.gsub(/[-_.]+/, "-")
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

        def python_version
          # TODO: Add better Python version detection using dependency versions
          # (e.g., Django 2.x implies Python 3)
          @python_version ||=
            user_specified_python_version ||
            python_version_from_compiled_requirements ||
            PythonVersions::PRE_INSTALLED_PYTHON_VERSIONS.first
        end

        def user_specified_python_version
          file_version = python_version_file&.content&.strip
          file_version ||= runtime_file_python_version

          return unless file_version
          return unless pyenv_versions.include?("#{file_version}\n")

          file_version
        end

        def runtime_file_python_version
          return unless runtime_file

          runtime_file.content.match(/(?<=python-).*/)&.to_s&.strip
        end

        def python_version_from_compiled_requirements
          PythonVersions::SUPPORTED_VERSIONS_TO_ITERATE.find do |version_string|
            version = Python::Version.new(version_string)
            compiled_file_python_requirement_markers.all? do |req|
              req.satisfied_by?(version)
            end
          end
        end

        def compiled_file_python_requirement_markers
          @python_requirement_strings ||=
            compiled_files.flat_map do |file|
              file.content.lines.
                select { |l| l.include?(";") && l.include?("python") }.
                map { |l| l.match(/python_version(?<req>.*?["'].*?['"])/) }.
                compact.
                map { |re| re.named_captures.fetch("req").gsub(/['"]/, "") }.
                select do |r|
                  requirement_class.new(r)
                  true
                rescue Gem::Requirement::BadRequirementError
                  false
                end
            end

          @python_requirement_strings.map { |r| requirement_class.new(r) }
        end

        def pyenv_versions
          @pyenv_versions ||= run_command("pyenv install --list")
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

        def python_version_file
          dependency_files.find { |f| f.name == ".python-version" }
        end

        def runtime_file
          dependency_files.find { |f| f.name.end_with?("runtime.txt") }
        end

        def requirement_class
          Python::Requirement
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
