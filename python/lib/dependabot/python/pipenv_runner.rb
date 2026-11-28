# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/python/file_parser"
require "dependabot/python/name_normaliser"
require "dependabot/python/subprocess_error_context"
require "json"
require "shellwords"
require "sorbet-runtime"

module Dependabot
  module Python
    class PipenvRunner
      extend T::Sig

      sig do
        params(
          dependency: T.nilable(Dependabot::Dependency),
          lockfile: T.nilable(Dependabot::DependencyFile),
          language_version_manager: LanguageVersionManager,
          dependency_files: T.nilable(T::Array[Dependabot::DependencyFile]),
          repo_contents_path: T.nilable(String),
          credentials: T::Array[Dependabot::Credential]
        )
          .void
      end
      def initialize(
        dependency:,
        lockfile:,
        language_version_manager:,
        dependency_files: nil,
        repo_contents_path: nil,
        credentials: []
      )
        @dependency = dependency
        @lockfile = lockfile
        @language_version_manager = language_version_manager
        @dependency_files = dependency_files
        @repo_contents_path = repo_contents_path
        @credentials = credentials
      end

      sig { params(constraint: T.nilable(String)).returns(String) }
      def run_upgrade(constraint)
        constraint = "" if constraint == "*"

        # Build the full package specification with extras
        extras_spec = extras_specification
        package_spec = "#{dependency_name}#{extras_spec}#{constraint}"

        index = dependency_index
        if index
          command = ["pyenv", "exec", "pipenv", "upgrade", "--verbose", "--index", index, package_spec]
          command << "--dev" if lockfile_section == "develop"
        else
          command = "pyenv exec pipenv upgrade --verbose #{package_spec}"
          command << " --dev" if lockfile_section == "develop"
        end

        fingerprint = +"pyenv exec pipenv upgrade --verbose"
        fingerprint << " --index <index>" if index
        fingerprint << " <dependency_name><extras><constraint>"

        run(command, fingerprint: fingerprint)
      end

      sig { params(constraint: T.nilable(String)).returns(T.nilable(String)) }
      def run_upgrade_and_fetch_version(constraint)
        run_upgrade(constraint)

        updated_lockfile = JSON.parse(File.read("Pipfile.lock"))

        fetch_version_from_parsed_lockfile(updated_lockfile)
      end

      # Called by Python::DependencyGrapher.
      sig { returns(String) }
      def run_pipenv_graph
        SharedHelpers.in_a_temporary_repo_directory(base_directory, repo_contents_path) do
          File.write(".python-version", language_version_manager.python_major_minor)
          write_temporary_dependency_files
          language_version_manager.install_required_python
          run_command("pyenv exec pipenv sync --dev", fingerprint: "pyenv exec pipenv sync --dev")
          run_command("pyenv exec pipenv graph --json", fingerprint: "pyenv exec pipenv graph --json")
        end
      end

      sig { params(command: SharedHelpers::Command, fingerprint: T.nilable(String)).returns(String) }
      def run(command, fingerprint: nil)
        run_command(
          "pyenv local #{language_version_manager.python_major_minor}",
          fingerprint: "pyenv local <python_major_minor>"
        )

        run_command(command, fingerprint: fingerprint)
      end

      private

      sig { returns(T.nilable(Dependabot::Dependency)) }
      attr_reader :dependency

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      attr_reader :lockfile

      sig { returns(LanguageVersionManager) }
      attr_reader :language_version_manager

      sig { returns(T.nilable(T::Array[Dependabot::DependencyFile])) }
      attr_reader :dependency_files

      sig { returns(T.nilable(String)) }
      attr_reader :repo_contents_path

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(Dependabot::Dependency) }
      def current_dependency
        T.must(dependency)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def write_temporary_dependency_files
        T.must(dependency_files)
         .reject { |f| f.name == ".python-version" }
         .each do |file|
          path = file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, file.content)
        end
      end

      sig { returns(String) }
      def base_directory
        dependency_files&.first&.directory || "/"
      end

      sig { returns(String) }
      def extras_specification
        extras = dependency_extras
        return "" if extras.nil? || extras.empty?

        "[#{extras.join(',')}]"
      end

      sig { returns(T.nilable(T::Array[String])) }
      def dependency_extras
        return nil unless lockfile

        lockfile_content = T.must(lockfile).content
        return nil unless lockfile_content

        parsed_lockfile = JSON.parse(lockfile_content)
        section_data = parsed_lockfile_section(parsed_lockfile, lockfile_section)
        return nil unless section_data

        dependency_data = lockfile_dependency_data(section_data)
        return nil unless dependency_data

        dependency_data["extras"]
      end

      sig { returns(T.nilable(String)) }
      def dependency_index
        entry = pipfile_dependency_entry
        return entry.index if entry

        dependency_lockfile_index
      end

      sig { returns(T.nilable(FileParser::PipfileDocument::Entry)) }
      def pipfile_dependency_entry
        pipfile = dependency_files&.find { |file| file.name == "Pipfile" }
        return unless pipfile

        group_keys = FileParser::PipfileFilesParser::DEPENDENCY_GROUP_KEYS
                     .find { |keys| keys.fetch(:lockfile) == lockfile_section }
        pipfile_group = group_keys&.fetch(:pipfile)
        return unless pipfile_group

        normalized_dependency_name = NameNormaliser.normalise(dependency_name)
        document = FileParser::PipfileDocument.from_file(pipfile)
        document.entries(pipfile_group)
                .find { |entry| NameNormaliser.normalise(entry.name) == normalized_dependency_name }
      end

      sig { returns(T.nilable(String)) }
      def dependency_lockfile_index
        lockfile_content = lockfile&.content
        return unless lockfile_content

        parsed_lockfile = JSON.parse(lockfile_content)
        section_data = parsed_lockfile_section(parsed_lockfile, lockfile_section)
        return unless section_data

        dependency_data = lockfile_dependency_data(section_data)
        return unless dependency_data

        index = dependency_data["index"]
        index if index.is_a?(String)
      end

      sig do
        params(section_data: T::Hash[String, T.untyped])
          .returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def lockfile_dependency_data(section_data)
        dependency_data = section_data[current_dependency.name] || section_data[dependency_name]
        dependency_data if dependency_data.is_a?(Hash)
      end

      sig { params(updated_lockfile: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
      def fetch_version_from_parsed_lockfile(updated_lockfile)
        section_data = parsed_lockfile_section(updated_lockfile, lockfile_section)
        return nil unless section_data

        lockfile_dependency_data(section_data)
          &.dig("version")
          &.gsub(/^==/, "")
      end

      sig { params(command: SharedHelpers::Command, fingerprint: T.nilable(String)).returns(String) }
      def run_command(command, fingerprint: nil)
        SharedHelpers.run_shell_command(command, env: pipenv_env_variables, fingerprint: fingerprint)
      rescue SharedHelpers::HelperSubprocessFailed => e
        SubprocessErrorContext.attach(
          e,
          command: command.is_a?(Array) ? Shellwords.join(command) : command,
          dependency_files: dependency_files || [lockfile].compact,
          credentials: credentials
        )
        raise
      end

      sig { returns(T.nilable(String)) }
      def lockfile_section
        if current_dependency.requirements.any?
          T.must(T.must(current_dependency.requirements.first).groups).first&.to_s
        else
          transitive_lockfile_section
        end
      end

      sig { returns(T.nilable(String)) }
      def transitive_lockfile_section
        parsed_lockfile = JSON.parse(T.must(T.must(lockfile).content))
        sections = Python::FileParser::DEPENDENCY_GROUP_KEYS.filter_map do |keys|
          section = keys.fetch(:lockfile)
          section_data = parsed_lockfile_section(parsed_lockfile, section)
          next unless section_data && lockfile_dependency_data(section_data)

          section
        end

        original_version = current_dependency.previous_version || current_dependency.version
        sections.find do |section|
          section_data = parsed_lockfile_section(parsed_lockfile, section)
          version = section_data && lockfile_dependency_data(section_data)&.dig("version")
          version&.gsub(/^===?/, "") == original_version
        end || sections.first
      end

      sig do
        params(
          parsed_lockfile: T::Hash[String, T.untyped],
          section: T.nilable(String)
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def parsed_lockfile_section(parsed_lockfile, section)
        return nil unless section

        section_data = parsed_lockfile[section]
        return section_data if section_data.is_a?(Hash)

        nil
      end

      sig { returns(String) }
      def dependency_name
        current_dependency.metadata_string(:original_name) || current_dependency.name
      end

      sig { returns(T::Hash[String, String]) }
      def pipenv_env_variables
        {
          "PIPENV_YES" => "true",        # Install new Python ver if needed
          "PIPENV_MAX_RETRIES" => "3",   # Retry timeouts
          "PIPENV_NOSPIN" => "1",        # Don't pollute logs with spinner
          "PIPENV_TIMEOUT" => "600",     # Set install timeout to 10 minutes
          "PIP_DEFAULT_TIMEOUT" => "60", # Set pip timeout to 1 minute
          "COLUMNS" => "250"             # Avoid line wrapping
        }
      end
    end
  end
end
