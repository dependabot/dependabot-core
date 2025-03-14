# typed: strict
# frozen_string_literal: true

require "open3"
require "dependabot/dependency"
require "dependabot/python/requirement_parser"
require "dependabot/python/file_fetcher"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/file_updater"
require "dependabot/shared_helpers"
require "dependabot/python/language_version_manager"
require "dependabot/python/native_helpers"
require "dependabot/python/name_normaliser"
require "dependabot/python/authed_url_builder"

module Dependabot
  module Python
    class FileUpdater
      # rubocop:disable Metrics/ClassLength
      class PipCompileFileUpdater
        extend T::Sig
        require_relative "requirement_replacer"
        require_relative "requirement_file_updater"
        require_relative "setup_file_sanitizer"

        UNSAFE_PACKAGES = T.let(%w(setuptools distribute pip).freeze, T::Array[String])
        INCOMPATIBLE_VERSIONS_REGEX = T.let(/There are incompatible versions in the resolved dependencies:.*\z/m,
                                            Regexp)
        WARNINGS = T.let(/\s*# WARNING:.*\Z/m, Regexp)
        UNSAFE_NOTE = T.let(/\s*# The following packages are considered to be unsafe.*\Z/m, Regexp)
        RESOLVER_REGEX = T.let(/(?<=--resolver=)(\w+)/, Regexp)
        NATIVE_COMPILATION_ERROR = T.let(
          "pip._internal.exceptions.InstallationSubprocessError: Getting requirements to build wheel exited with 1",
          String
        )

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            index_urls: T.nilable(T::Array[String])
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:, index_urls: nil)
          @dependencies = T.let(dependencies, T::Array[Dependabot::Dependency])
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @index_urls = T.let(index_urls, T.nilable(T::Array[String]))
          @build_isolation = T.let(true, T::Boolean)
          @sanitized_setup_file_content = T.let({}, T::Hash[String, String])
          @requirement_map = T.let(nil, T.nilable(T::Hash[String, T::Array[String]]))
          @python_requirement_parser = T.let(nil, T.nilable(FileParser::PythonRequirementParser))
          @language_version_manager = T.let(nil, T.nilable(LanguageVersionManager))
          @setup_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @setup_cfg_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @pip_compile_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @compiled_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
        end

        sig { returns(T.nilable(T::Array[Dependabot::DependencyFile])) }
        def updated_dependency_files
          @updated_dependency_files = T.let(fetch_updated_dependency_files,
                                            T.nilable(T::Array[Dependabot::DependencyFile]))
        end

        private

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def dependency
          # For now, we'll only ever be updating a single dependency
          dependencies.first
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
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

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def compile_new_requirement_files
          SharedHelpers.in_a_temporary_directory do
            write_updated_dependency_files
            language_version_manager.install_required_python

            filenames_to_compile.each do |filename|
              compile_file(filename)
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

        sig { params(filename: String).void }
        def compile_file(filename)
          # Shell out to pip-compile, generate a new set of requirements.
          # This is slow, as pip-compile needs to do installs.
          options = pip_compile_options(filename)
          options_fingerprint = pip_compile_options_fingerprint(options)

          name_part = "pyenv exec pip-compile " \
                      "#{options} -P " \
                      "#{T.must(dependency).name}"
          fingerprint_name_part = "pyenv exec pip-compile " \
                                  "#{options_fingerprint} -P " \
                                  "<dependency_name>"

          version_part = "#{T.must(dependency).version} #{filename}"
          fingerprint_version_part = "<dependency_version> <filename>"

          # Don't escape pyenv `dep-name==version` syntax
          run_pip_compile_command(
            "#{SharedHelpers.escape_command(name_part)}==" \
            "#{SharedHelpers.escape_command(version_part)}",
            allow_unsafe_shell_command: true,
            fingerprint: "#{fingerprint_name_part}==#{fingerprint_version_part}"
          )
        rescue SharedHelpers::HelperSubprocessFailed => e
          retry_count ||= 0
          retry_count += 1
          if compilation_error?(e) && retry_count <= 1
            @build_isolation = false
            retry
          end

          raise
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T::Boolean) }
        def compilation_error?(error)
          error.message.include?(NATIVE_COMPILATION_ERROR)
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
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

        sig do
          params(updated_files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile])
        end
        def update_uncompiled_files(updated_files)
          updated_filenames = updated_files.map(&:name)
          old_reqs = T.must(T.must(dependency).previous_requirements)
                      .reject { |r| updated_filenames.include?(r[:file]) }
          new_reqs = T.must(dependency).requirements
                      .reject { |r| updated_filenames.include?(r[:file]) }

          return [] if new_reqs.none?

          files = dependency_files
                  .reject { |file| updated_filenames.include?(file.name) }

          args = dependency.to_h
          args = args.keys.to_h { |k| [k.to_sym, args[k]] }
          args[:requirements] = new_reqs
          args[:previous_requirements] = old_reqs

          RequirementFileUpdater.new(
            dependencies: [Dependency.new(**T.unsafe(args))],
            dependency_files: files,
            credentials: credentials
          ).updated_dependency_files
        end

        sig { params(cmd: String, fingerprint: String, env: T.nilable(T::Hash[String, String]), allow_unsafe_shell_command: T::Boolean).returns(String) }
        def run_command(cmd, fingerprint:, env: python_env, allow_unsafe_shell_command: false)
          SharedHelpers.run_shell_command(
            cmd,
            env: env,
            allow_unsafe_shell_command: allow_unsafe_shell_command,
            fingerprint: fingerprint,
            stderr_to_stdout: true
          )
        rescue SharedHelpers::HelperSubprocessFailed => e
          stdout = e.message

          if stdout.match?(INCOMPATIBLE_VERSIONS_REGEX)
            raise DependencyFileNotResolvable, stdout.match(INCOMPATIBLE_VERSIONS_REGEX)
          end

          raise
        end

        sig { params(command: String, fingerprint: String, allow_unsafe_shell_command: T::Boolean).returns(String) }
        def run_pip_compile_command(command, fingerprint:, allow_unsafe_shell_command: false)
          run_command(
            "pyenv local #{language_version_manager.python_major_minor}",
            fingerprint: "pyenv local <python_major_minor>"
          )

          run_command(
            command,
            allow_unsafe_shell_command: allow_unsafe_shell_command,
            fingerprint: fingerprint
          )
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def python_env
          env = {}

          # Handle Apache Airflow 1.10.x installs
          if dependency_files.any? { |f| T.must(f.content).include?("apache-airflow") }
            if dependency_files.any? { |f| T.must(f.content).include?("unidecode") }
              env["AIRFLOW_GPL_UNIDECODE"] = "yes"
            else
              env["SLUGIFY_USES_TEXT_UNIDECODE"] = "yes"
            end
          end

          env
        end

        sig { void }
        def write_updated_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, freeze_dependency_requirement(file))
          end

          # Overwrite the .python-version with updated content
          File.write(".python-version", language_version_manager.python_major_minor)

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

        sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def sanitized_setup_file_content(file)
          return @sanitized_setup_file_content[file.name] if @sanitized_setup_file_content[file.name]

          @sanitized_setup_file_content[file.name] =
            SetupFileSanitizer
            .new(setup_file: file, setup_cfg: setup_cfg(file))
            .sanitized_content
        end

        sig { params(file: DependencyFile).returns(T.nilable(Dependabot::DependencyFile)) }
        def setup_cfg(file)
          dependency_files.find do |f|
            f.name == file.name.sub(/\.py$/, ".cfg")
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def freeze_dependency_requirement(file)
          return file.content unless file.name.end_with?(".in")

          old_req = T.must(T.must(dependency).previous_requirements)
                     .find { |r| r[:file] == file.name }

          return file.content unless old_req
          return file.content if old_req == "==#{T.must(dependency).version}"

          RequirementReplacer.new(
            content: file.content,
            dependency_name: T.must(dependency).name,
            old_requirement: old_req[:requirement],
            new_requirement: "==#{T.must(dependency).version}",
            index_urls: @index_urls
          ).updated_content
        end

        sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def update_dependency_requirement(file)
          return file.content unless file.name.end_with?(".in")

          old_req = T.must(T.must(dependency).previous_requirements)
                     .find { |r| r[:file] == file.name }
          new_req = T.must(dependency).requirements
                     .find { |r| r[:file] == file.name }
          return file.content unless old_req&.fetch(:requirement)
          return file.content if old_req == new_req

          RequirementReplacer.new(
            content: file.content,
            dependency_name: T.must(dependency).name,
            old_requirement: old_req[:requirement],
            new_requirement: T.must(new_req)[:requirement],
            index_urls: @index_urls
          ).updated_content
        end

        sig { params(updated_content: String, file: Dependabot::DependencyFile).returns(String) }
        def post_process_compiled_file(updated_content, file)
          content = replace_header_with_original(updated_content, T.must(file.content))
          content = remove_new_warnings(content, T.must(file.content))
          content = update_hashes_if_required(content, T.must(file.content))
          replace_absolute_file_paths(content, T.must(file.content))
        end

        sig { params(updated_content: String, original_content: String).returns(String) }
        def replace_header_with_original(updated_content, original_content)
          original_header_lines =
            original_content.lines.take_while { |l| l.start_with?("#") }

          updated_content_lines =
            updated_content.lines.drop_while { |l| l.start_with?("#") }

          [*original_header_lines, *updated_content_lines].join
        end

        sig { params(updated_content: String, original_content: String).returns(String) }
        def replace_absolute_file_paths(updated_content, original_content)
          content = updated_content

          update_count = 0
          original_content.lines.each do |original_line|
            next unless original_line.start_with?("-e")
            next update_count += 1 if updated_content.include?(original_line)

            line_to_update =
              updated_content.lines
                             .select { |l| l.start_with?("-e") }
                             .at(update_count)
            raise "Mismatch in editable requirements!" unless line_to_update

            content = content.gsub(line_to_update, original_line)
            update_count += 1
          end

          content
        end

        sig { params(updated_content: String, original_content: String).returns(String) }
        def remove_new_warnings(updated_content, original_content)
          content = updated_content

          content = content.sub(WARNINGS, "\n") if content.match?(WARNINGS) && !original_content.match?(WARNINGS)

          if content.match?(UNSAFE_NOTE) &&
             !original_content.match?(UNSAFE_NOTE)
            content = content.sub(UNSAFE_NOTE, "\n")
          end

          content
        end

        sig { params(updated_content: String, original_content: String).returns(String) }
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
              ).sort.join(T.must(hash_separator(mtch.to_s)))
            )

            updated_content_with_hashes = updated_content_with_hashes
                                          .gsub(mtch.to_s, updated_string)
          end
          updated_content_with_hashes
        end

        sig { params(updated_content: String, original_content: String).returns(T::Array[T.untyped]) }
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

        sig { params(name: String, version: String, algorithm: String).returns(T::Array[String]) }
        def package_hashes_for(name:, version:, algorithm:)
          index_urls = @index_urls || [nil]
          hashes = []

          index_urls.each do |index_url|
            args = [name, version, algorithm]
            args << index_url if index_url

            begin
              native_helper_hashes = T.cast(
                SharedHelpers.run_helper_subprocess(
                  command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
                  function: "get_dependency_hash",
                  args: args
                ),
                T::Array[T::Hash[String, String]]
              ).map { |h| "--hash=#{algorithm}:#{h['hash']}" }

              hashes.concat(native_helper_hashes)
            rescue SharedHelpers::HelperSubprocessFailed => e
              raise unless e.error_class.include?("PackageNotFoundError")

              next
            end
          end

          hashes
        end

        sig { params(requirement_string: String).returns(T.nilable(String)) }
        def hash_separator(requirement_string)
          hash_regex = RequirementParser::HASH
          return unless requirement_string.match?(hash_regex)

          # rubocop:disable Layout/LineLength
          current_separator =
            T.must(requirement_string.match(/#{hash_regex}((?<separator>\s*\\?\s*?)#{hash_regex})*/)).named_captures.fetch("separator")

          # rubocop(Layout/LineLength): Line is too long. [125/120]
          default_separator =
            T.must(T.must(requirement_string
            .match(RequirementParser::HASH)).pre_match.match(/(?<separator>\s*\\?\s*?)\z/)).named_captures.fetch("separator")

          current_separator || default_separator
        end

        sig { params(options: String).returns(String) }
        def pip_compile_options_fingerprint(options)
          options.sub(
            /--output-file=\S+/, "--output-file=<output_file>"
          ).sub(
            /--index-url=\S+/, "--index-url=<index_url>"
          ).sub(
            /--extra-index-url=\S+/, "--extra-index-url=<extra_index_url>"
          )
        end

        sig { params(filename: String).returns(String) }
        def pip_compile_options(filename)
          options = @build_isolation ? ["--build-isolation"] : ["--no-build-isolation"]
          options += pip_compile_index_options

          if (requirements_file = compiled_file_for_filename(filename))
            options += pip_compile_options_from_compiled_file(requirements_file)
          end

          options.join(" ")
        end

        sig { params(requirements_file: T.nilable(Dependabot::DependencyFile)).returns(T::Array[String]) }
        def pip_compile_options_from_compiled_file(requirements_file)
          options = ["--output-file=#{T.must(requirements_file).name}"]

          options << "--no-emit-index-url" unless T.must(T.must(requirements_file).content).include?("index-url http")

          options << "--generate-hashes" if T.must(T.must(requirements_file).content).include?("--hash=sha")

          options << "--allow-unsafe" if includes_unsafe_packages?(T.must(T.must(requirements_file).content))

          options << "--no-annotate" unless T.must(T.must(requirements_file).content).include?("# via ")

          options << "--no-header" unless T.must(T.must(requirements_file).content).include?("autogenerated by pip-c")

          options << "--pre" if T.must(T.must(requirements_file).content).include?("--pre")

          options << "--strip-extras" if T.must(T.must(requirements_file).content).include?("--strip-extras")

          if (resolver = RESOLVER_REGEX.match(T.must(requirements_file).content))
            options << "--resolver=#{resolver}"
          end

          options
        end

        sig { returns(T::Array[String]) }
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

        sig { params(content: String).returns(T::Boolean) }
        def includes_unsafe_packages?(content)
          UNSAFE_PACKAGES.any? { |n| content.match?(/^#{Regexp.quote(n)}==/) }
        end

        sig { returns(T::Array[String]) }
        def filenames_to_compile
          files_from_reqs =
            T.must(dependency).requirements
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

        sig { params(filename: String).returns(T.nilable(Dependabot::DependencyFile)) }
        def compiled_file_for_filename(filename)
          compiled_file =
            compiled_files
            .find { |f| T.must(f.content).match?(output_file_regex(filename)) }

          compiled_file ||=
            compiled_files
            .find { |f| f.name == filename.gsub(/\.in$/, ".txt") }

          compiled_file
        end

        sig { params(filename: T.any(String, Symbol)).returns(String) }
        def output_file_regex(filename)
          "--output-file[=\s]+.*\s#{Regexp.escape(filename)}\s*$"
        end

        sig { params(compiled_file: T.nilable(Dependabot::DependencyFile)).returns(T::Boolean) }
        def compiled_file_includes_dependency?(compiled_file)
          return false unless compiled_file

          regex = RequirementParser::INSTALL_REQ_WITH_REQUIREMENT

          matches = []
          T.must(compiled_file.content).scan(regex) { matches << Regexp.last_match }
          matches.any? { |m| normalise(m[:name]) == T.must(dependency).name }
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
        end

        # If the files we need to update require one another then we need to
        # update them in the right order
        sig { params(filenames: T::Array[String]).returns(T::Array[String]) }
        def order_filenames_for_compilation(filenames)
          ordered_filenames = T.let([], T::Array[String])

          while (remaining_filenames = filenames - ordered_filenames).any?
            ordered_filenames +=
              remaining_filenames
              .reject do |fn|
                unupdated_reqs = (requirement_map[fn] || []) - ordered_filenames
                unupdated_reqs.intersect?(filenames)
              end
          end

          ordered_filenames
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        def requirement_map
          child_req_regex = Python::FileFetcher::CHILD_REQUIREMENT_REGEX
          @requirement_map ||=
            pip_compile_files.each_with_object({}) do |file, req_map|
              paths = T.must(file.content).scan(child_req_regex).flatten
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

        sig { returns(Dependabot::Python::FileParser::PythonRequirementParser) }
        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        sig { returns(Dependabot::Python::LanguageVersionManager) }
        def language_version_manager
          @language_version_manager ||=
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def setup_files
          dependency_files.select { |f| f.name.end_with?("setup.py") }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def pip_compile_files
          dependency_files.select { |f| f.name.end_with?(".in") }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def compiled_files
          dependency_files.select { |f| f.name.end_with?(".txt") }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def setup_cfg_files
          dependency_files.select { |f| f.name.end_with?("setup.cfg") }
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
