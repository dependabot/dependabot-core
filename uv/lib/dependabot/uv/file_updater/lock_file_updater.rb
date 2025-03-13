# typed: true
# frozen_string_literal: true

require "toml-rb"
require "open3"
require "dependabot/dependency"
require "dependabot/shared_helpers"
require "dependabot/uv/language_version_manager"
require "dependabot/uv/version"
require "dependabot/uv/requirement"
require "dependabot/uv/file_parser/python_requirement_parser"
require "dependabot/uv/file_updater"
require "dependabot/uv/native_helpers"
require "dependabot/uv/name_normaliser"

module Dependabot
  module Uv
    class FileUpdater
      class LockFileUpdater
        require_relative "pyproject_preparer"

        attr_reader :dependencies
        attr_reader :dependency_files
        attr_reader :credentials
        attr_reader :index_urls

        def initialize(dependencies:, dependency_files:, credentials:, index_urls: nil)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @index_urls = index_urls
        end

        def updated_dependency_files
          @updated_dependency_files ||= fetch_updated_dependency_files
        end

        private

        def dependency
          # For now, we'll only ever be updating a single dependency
          dependencies.first
        end

        def fetch_updated_dependency_files
          updated_files = []

          if file_changed?(pyproject)
            updated_files <<
              updated_file(
                file: pyproject,
                content: updated_pyproject_content
              )
          end

          if lockfile
            # Use updated_lockfile_content which might raise if the lockfile doesn't change
            new_content = updated_lockfile_content
            raise "Expected lockfile to change!" if lockfile.content == new_content

            updated_files << updated_file(file: lockfile, content: new_content)
          end

          updated_files
        end

        def updated_pyproject_content
          content = pyproject.content
          return content unless file_changed?(pyproject)

          updated_content = content.dup

          dependency.requirements.zip(dependency.previous_requirements).each do |new_r, old_r|
            next unless new_r[:file] == pyproject.name && old_r[:file] == pyproject.name

            updated_content = replace_dep(dependency, updated_content, new_r, old_r)
          end

          raise DependencyFileContentNotChanged, "Content did not change!" if content == updated_content

          updated_content
        end

        def replace_dep(dep, content, new_r, old_r)
          new_req = new_r[:requirement]
          old_req = old_r[:requirement]

          declaration_regex = declaration_regex(dep, old_r)
          declaration_match = content.match(declaration_regex)
          if declaration_match
            declaration = declaration_match[:declaration]
            new_declaration = declaration.sub(old_req, new_req)
            content.sub(declaration, new_declaration)
          else
            content
          end
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            begin
              original_content = lockfile.content
              # Extract the original requires-python value to preserve it
              original_requires_python = original_content
                                         .match(/requires-python\s*=\s*["']([^"']+)["']/)&.captures&.first

              # Use the original Python version requirement for the update if one exists
              with_original_python_version(original_requires_python) do
                new_lockfile = updated_lockfile_content_for(prepared_pyproject)

                # Use direct string replacement to preserve the exact format
                # Match the dependency section and update only the version
                dependency_section_pattern = /
                  (\[\[package\]\]\s*\n
                   .*?name\s*=\s*["']#{Regexp.escape(dependency.name)}["']\s*\n
                   .*?)
                  (version\s*=\s*["'][^"']+["'])
                  (.*?)
                  (\[\[package\]\]|\z)
                /xm

                result = original_content.sub(dependency_section_pattern) do
                  section_start = Regexp.last_match(1)
                  version_line = "version = \"#{dependency.version}\""
                  section_end = Regexp.last_match(3)
                  next_section_or_end = Regexp.last_match(4)

                  "#{section_start}#{version_line}#{section_end}#{next_section_or_end}"
                end

                # If the content didn't change and we expect it to, something went wrong
                if result == original_content
                  Dependabot.logger.warn("Package section not found for #{dependency.name}, falling back to raw update")
                  result = new_lockfile
                end

                # Restore the original requires-python if it exists
                if original_requires_python
                  result = result.gsub(/requires-python\s*=\s*["'][^"']+["']/,
                                       "requires-python = \"#{original_requires_python}\"")
                end

                result
              end
            end
        end

        # Helper method to temporarily override Python version during operations
        def with_original_python_version(original_requires_python)
          if original_requires_python
            original_python_version = @original_python_version
            @original_python_version = original_requires_python
            result = yield
            @original_python_version = original_python_version
            result
          else
            yield
          end
        end

        def prepared_pyproject
          @prepared_pyproject ||=
            begin
              content = updated_pyproject_content
              content = sanitize(content)
              content = freeze_other_dependencies(content)
              content = update_python_requirement(content)
              content
            end
        end

        def freeze_other_dependencies(pyproject_content)
          PyprojectPreparer
            .new(pyproject_content: pyproject_content, lockfile: lockfile)
            .freeze_top_level_dependencies_except(dependencies)
        end

        def update_python_requirement(pyproject_content)
          PyprojectPreparer
            .new(pyproject_content: pyproject_content)
            .update_python_requirement(language_version_manager.python_version)
        end

        def sanitize(pyproject_content)
          PyprojectPreparer
            .new(pyproject_content: pyproject_content)
            .sanitize
        end

        def updated_lockfile_content_for(pyproject_content)
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_temporary_dependency_files(pyproject_content)

              # Install Python before writing .python-version to make sure we use a version that's available
              language_version_manager.install_required_python

              # Determine the Python version to use after installation
              python_version = determine_python_version

              # Now write the .python-version file with a version we know is installed
              File.write(".python-version", python_version)

              run_update_command

              File.read("uv.lock")
            end
          end
        end

        def run_update_command
          command = "pyenv exec uv lock --upgrade-package #{dependency.name}"
          fingerprint = "pyenv exec uv lock --upgrade-package <dependency_name>"

          run_command(command, fingerprint:)
        end

        def run_command(command, fingerprint: nil)
          SharedHelpers.run_shell_command(command, fingerprint: fingerprint)
        end

        def write_temporary_dependency_files(pyproject_content)
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          # Only write the .python-version file after the language version manager has
          # installed the required Python version to ensure it's available
          # Overwrite the pyproject with updated content
          File.write("pyproject.toml", pyproject_content)
        end

        def determine_python_version
          # Check available Python versions through pyenv
          available_versions = nil
          begin
            available_versions = SharedHelpers.run_shell_command("pyenv versions --bare")
                                              .split("\n")
                                              .map(&:strip)
                                              .reject(&:empty?)
          rescue StandardError => e
            Dependabot.logger.warn("Error checking available Python versions: #{e}")
          end

          # Try to find the closest match for our priority order
          preferred_version = find_preferred_version(available_versions)

          if preferred_version
            # Just return the major.minor version string
            preferred_version.match(/^(\d+\.\d+)/)[1]
          else
            # If all else fails, use "system" which should work with whatever Python is available
            "system"
          end
        end

        def find_preferred_version(available_versions)
          return nil unless available_versions&.any?

          # Try each strategy in order of preference
          try_version_from_file(available_versions) ||
            try_version_from_requires_python(available_versions) ||
            try_highest_python3_version(available_versions)
        end

        def try_version_from_file(available_versions)
          python_version_file = dependency_files.find { |f| f.name == ".python-version" }
          return nil unless python_version_file && !python_version_file.content.strip.empty?

          requested_version = python_version_file.content.strip
          return requested_version if version_available?(available_versions, requested_version)

          Dependabot.logger.info("Python version #{requested_version} from .python-version not available")
          nil
        end

        def try_version_from_requires_python(available_versions)
          return nil unless @original_python_version

          version_match = @original_python_version.match(/(\d+\.\d+)/)
          return nil unless version_match

          requested_version = version_match[1]
          return requested_version if version_available?(available_versions, requested_version)

          Dependabot.logger.info("Python version #{requested_version} from requires-python not available")
          nil
        end

        def try_highest_python3_version(available_versions)
          python3_versions = available_versions
                             .select { |v| v.match(/^3\.\d+/) }
                             .sort_by { |v| Gem::Version.new(v.match(/^(\d+\.\d+)/)[1]) }
                             .reverse

          python3_versions.first # returns nil if array is empty
        end

        def version_available?(available_versions, requested_version)
          # Check if the exact version or a version with the same major.minor is available
          available_versions.any? do |v|
            v == requested_version || v.start_with?("#{requested_version}.")
          end
        end

        def sanitize_env_name(url)
          url.gsub(%r{^https?://}, "").gsub(/[^a-zA-Z0-9]/, "_").upcase
        end

        def declaration_regex(dep, old_req)
          escaped_name = Regexp.escape(dep.name)
          # Extract the requirement operator and version
          operator = old_req.fetch(:requirement).match(/^(.+?)[0-9]/)&.captures&.first
          # Escape special regex characters in the operator
          escaped_operator = Regexp.escape(operator) if operator

          # Match various formats of dependency declarations:
          # 1. "dependency==1.0.0" (with quotes around the entire string)
          # 2. dependency==1.0.0 (without quotes)
          # The declaration should only include the package name, operator, and version
          # without the enclosing quotes
          /
            ["']?(?<declaration>#{escaped_name}\s*#{escaped_operator}[\d\.\*]+)["']?
          /x
        end

        def escape(name)
          Regexp.escape(name).gsub("\\-", "[-_.]")
        end

        def file_changed?(file)
          return false unless file

          dependencies.any? do |dep|
            dep.requirements.any? { |r| r[:file] == file.name } &&
              requirement_changed?(file, dep)
          end
        end

        def requirement_changed?(file, dependency)
          changed_requirements =
            dependency.requirements - dependency.previous_requirements

          changed_requirements.any? { |f| f[:file] == file.name }
        end

        def updated_file(file:, content:)
          updated_file = file.dup
          updated_file.content = content
          updated_file
        end

        def normalise(name)
          NameNormaliser.normalise(name)
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

        def pyproject
          @pyproject ||=
            dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        def lockfile
          @lockfile ||= uv_lock
        end

        def python_helper_path
          NativeHelpers.python_helper_path
        end

        def uv_lock
          dependency_files.find { |f| f.name == "uv.lock" }
        end
      end
    end
  end
end
