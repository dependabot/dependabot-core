# typed: strict
# frozen_string_literal: true

require "open3"
require "dependabot/dependency"
require "dependabot/python/requirement_parser"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/file_updater"
require "dependabot/python/language_version_manager"
require "dependabot/shared_helpers"
require "dependabot/python/native_helpers"
require "dependabot/python/pipenv_runner"
require "sorbet-runtime"

module Dependabot
  module Python
    class FileUpdater
      class PipfileFileUpdater
        extend T::Sig

        require_relative "pipfile_preparer"
        require_relative "pipfile_manifest_updater"
        require_relative "setup_file_sanitizer"

        DEPENDENCY_TYPES = T.let(%w(packages dev-packages).freeze, T::Array[String])

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        # rubocop:disable Metrics/AbcSize
        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String)
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:, repo_contents_path:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @repo_contents_path = repo_contents_path
          @updated_pipfile_content = T.let(nil, T.nilable(String))
          @updated_lockfile_content = T.let(nil, T.nilable(String))
          @updated_generated_files = T.let(nil, T.nilable(T::Hash[Symbol, String]))
          @pipfile = T.let(nil, T.nilable(Dependabot::DependencyFile))
          @lockfile = T.let(nil, T.nilable(Dependabot::DependencyFile))
          @setup_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @setup_cfg_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @requirements_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @updated_dependency_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @updated_pipfile_content = T.let(nil, T.nilable(String))
          @parsed_lockfile = T.let(nil, T.nilable(T::Hash[String, T::Hash[String, Object]]))
          @pipenv_runner = T.let(nil, T.nilable(PipenvRunner))
          @language_version_manager = T.let(nil, T.nilable(LanguageVersionManager))
          @sanitized_setup_file_content = T.let({}, T.untyped)
          @python_requirement_parser = T.let(nil, T.nilable(FileParser::PythonRequirementParser))
        end

        # rubocop:enable Metrics/AbcSize

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_dependency_files
          @updated_dependency_files ||= fetch_updated_dependency_files
        end

        private

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def dependency
          # For now, we'll only ever be updating a single dependency
          dependencies.first
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def fetch_updated_dependency_files
          updated_files = []

          if pipfile&.content != updated_pipfile_content
            updated_files <<
              updated_file(file: T.must(pipfile), content: T.must(updated_pipfile_content))
          end

          if lockfile
            raise "Expected Pipfile.lock to change!" if lockfile&.content == updated_lockfile_content

            updated_files <<
              updated_file(file: T.must(lockfile), content: updated_lockfile_content)
          end

          updated_files += updated_generated_requirements_files
          updated_files
        end

        sig { returns(T.nilable(String)) }
        def updated_pipfile_content
          @updated_pipfile_content ||=
            PipfileManifestUpdater.new(
              dependencies: dependencies,
              manifest: T.must(pipfile)
            ).updated_manifest_content
        end

        sig { returns(String) }
        def updated_lockfile_content
          @updated_lockfile_content ||=
            updated_generated_files.fetch(:lockfile)
        end

        sig { returns(T::Boolean) }
        def generate_updated_requirements_files?
          return true if generated_requirements_files("default").any?

          generated_requirements_files("develop").any?
        end

        sig { params(type: String).returns(T::Array[Dependabot::DependencyFile]) }
        def generated_requirements_files(type)
          return [] unless lockfile

          pipfile_lock_deps = parsed_lockfile[type]&.keys&.sort || []
          return [] unless pipfile_lock_deps.any?

          regex = RequirementParser::INSTALL_REQ_WITH_REQUIREMENT

          # Find any requirement files that list the same dependencies as
          # the (old) Pipfile.lock. Any such files were almost certainly
          # generated using `pipenv requirements`
          requirements_files.select do |req_file|
            deps = []
            req_file.content&.scan(regex) { deps << Regexp.last_match }
            deps = deps.map { |m| m[:name] }
            deps.sort == pipfile_lock_deps
          end
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_generated_requirements_files
          updated_files = []

          generated_requirements_files("default").each do |file|
            next if file.content == updated_req_content

            updated_files <<
              updated_file(file: file, content: updated_req_content)
          end

          generated_requirements_files("develop").each do |file|
            next if file.content == updated_dev_req_content

            updated_files <<
              updated_file(file: file, content: updated_dev_req_content)
          end

          updated_files
        end

        sig { returns(String) }
        def updated_req_content
          updated_generated_files.fetch(:requirements_txt)
        end

        sig { returns(String) }
        def updated_dev_req_content
          updated_generated_files.fetch(:dev_requirements_txt)
        end

        sig { returns(String) }
        def prepared_pipfile_content
          content = updated_pipfile_content
          content = add_private_sources(content.to_s)
          content = update_python_requirement(content)
          content = update_ssl_requirement(content, updated_pipfile_content.to_s)

          content
        end

        sig { params(pipfile_content: String).returns(String) }
        def update_python_requirement(pipfile_content)
          PipfilePreparer
            .new(pipfile_content: pipfile_content)
            .update_python_requirement(language_version_manager.python_major_minor)
        end

        sig { params(pipfile_content: String, parsed_file: String).returns(String) }
        def update_ssl_requirement(pipfile_content, parsed_file)
          Python::FileUpdater::PipfilePreparer
            .new(pipfile_content: pipfile_content)
            .update_ssl_requirement(parsed_file)
        end

        sig { params(pipfile_content: String).returns(String) }
        def add_private_sources(pipfile_content)
          PipfilePreparer
            .new(pipfile_content: pipfile_content)
            .replace_sources(credentials)
        end

        sig { returns(T::Hash[Symbol, String]) }
        def updated_generated_files
          @updated_generated_files ||=
            SharedHelpers.in_a_temporary_repo_directory(T.must(dependency_files.first).directory, repo_contents_path) do
              SharedHelpers.with_git_configured(credentials: credentials) do
                write_temporary_dependency_files(prepared_pipfile_content)
                install_required_python

                pipenv_runner&.run_upgrade("==#{dependency&.version}")

                result = { lockfile: File.read("Pipfile.lock") }
                result[:lockfile] = post_process_lockfile(result[:lockfile])

                # Generate updated requirement.txt entries, if needed.
                if generate_updated_requirements_files?
                  generate_updated_requirements_files

                  result[:requirements_txt] = File.read("req.txt")
                  result[:dev_requirements_txt] = File.read("dev-req.txt")
                end

                result
              end
            end
        end

        sig { params(updated_lockfile_content: String).returns(String) }
        def post_process_lockfile(updated_lockfile_content)
          new_lockfile_json = JSON.parse(updated_lockfile_content.dup)

          update_lockfile_metadata(new_lockfile_json)

          format_lockfile_json(new_lockfile_json)
        end

        sig { params(lockfile_json: T::Hash[String, T.untyped]).void }
        def update_lockfile_metadata(lockfile_json)
          pipfile_hash = pipfile_hash_for(updated_pipfile_content.to_s)
          original_reqs = T.must(parsed_lockfile["_meta"])["requires"]
          original_source = T.must(parsed_lockfile["_meta"])["sources"]

          lockfile_json["_meta"]["hash"]["sha256"] = pipfile_hash
          lockfile_json["_meta"]["requires"] = original_reqs
          lockfile_json["_meta"]["sources"] = original_source
        end

        sig { params(lockfile_json: T::Hash[String, T.untyped]).returns(String) }
        def format_lockfile_json(lockfile_json)
          JSON.pretty_generate(lockfile_json, indent: "    ")
              .gsub(/\{\n\s*\}/, "{}")
              .gsub(/\}\z/, "}\n")
        end

        sig { returns(Integer) }
        def generate_updated_requirements_files
          req_content = run_pipenv_command(
            "pyenv exec pipenv requirements"
          )
          File.write("req.txt", req_content)

          dev_req_content = run_pipenv_command(
            "pyenv exec pipenv requirements --dev"
          )
          File.write("dev-req.txt", dev_req_content)
        end

        sig { params(command: String).returns(String) }
        def run_command(command)
          SharedHelpers.run_shell_command(command)
        end

        sig { params(command: String).returns(String) }
        def run_pipenv_command(command)
          T.must(pipenv_runner).run(command)
        end

        sig { params(pipfile_content: Object).returns(Integer) }
        def write_temporary_dependency_files(pipfile_content)
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
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

          # Overwrite the pipfile with updated content
          File.write("Pipfile", pipfile_content)
        end

        sig { returns(T.nilable(String)) }
        def install_required_python
          # Initialize a git repo to appease pip-tools
          begin
            run_command("git init") if setup_files.any?
          rescue Dependabot::SharedHelpers::HelperSubprocessFailed
            nil
          end

          language_version_manager.install_required_python
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def sanitized_setup_file_content(file)
          @sanitized_setup_file_content ||= {}
          return @sanitized_setup_file_content[file.name] if @sanitized_setup_file_content[file.name]

          @sanitized_setup_file_content[file.name] =
            SetupFileSanitizer
            .new(setup_file: file, setup_cfg: setup_cfg(file))
            .sanitized_content
        end

        sig { params(file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::DependencyFile)) }
        def setup_cfg(file)
          dependency_files.find do |f|
            f.name == file.name.sub(/\.py$/, ".cfg")
          end
        end

        sig do
          params(
            pipfile_content: String
          ).returns(
            T.nilable(
              T.any(
                T::Hash[String, T.untyped],
                String,
                T::Array[T::Hash[String, T.untyped]]
              )
            )
          )
        end
        def pipfile_hash_for(pipfile_content)
          SharedHelpers.in_a_temporary_directory do |dir|
            File.write(File.join(dir, "Pipfile"), pipfile_content)
            SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
              function: "get_pipfile_hash",
              args: [T.cast(dir, Pathname).to_s]
            )
          end
        end

        sig { params(file: Dependabot::DependencyFile, content: String).returns(Dependabot::DependencyFile) }
        def updated_file(file:, content:)
          updated_file = file.dup
          updated_file.content = content
          updated_file
        end

        sig { returns(FileParser::PythonRequirementParser) }
        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        sig { returns(LanguageVersionManager) }
        def language_version_manager
          @language_version_manager ||=
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            )
        end

        sig { returns(T.nilable(PipenvRunner)) }
        def pipenv_runner
          @pipenv_runner ||=
            PipenvRunner.new(
              dependency: T.must(dependency),
              lockfile: lockfile,
              language_version_manager: language_version_manager
            )
        end

        sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
        def parsed_lockfile
          @parsed_lockfile ||= JSON.parse(T.must(lockfile&.content))
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pipfile
          @pipfile ||= dependency_files.find { |f| f.name == "Pipfile" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def lockfile
          @lockfile ||= dependency_files.find { |f| f.name == "Pipfile.lock" }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def setup_files
          dependency_files.select { |f| f.name.end_with?("setup.py") }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def setup_cfg_files
          dependency_files.select { |f| f.name.end_with?("setup.cfg") }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def requirements_files
          dependency_files.select { |f| f.name.end_with?(".txt") }
        end
      end
    end
  end
end
