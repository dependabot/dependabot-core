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
              new_lockfile = updated_lockfile_content_for(prepared_pyproject)

              # Preserve the original Python version if specified in the UV format
              if lockfile.content.include?("requires-python")
                original_python_version = lockfile.content.match(/^requires-python = ["'](.+)["']/i)&.captures&.first
                if original_python_version
                  new_lockfile.sub!(/^requires-python = ["'].+["']/i,
                                    "requires-python = \"#{original_python_version}\"")
                end
              end

              new_lockfile
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

              language_version_manager.install_required_python

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

          # Overwrite the .python-version with updated content
          File.write(".python-version", language_version_manager.python_major_minor)

          # Overwrite the pyproject with updated content
          File.write("pyproject.toml", pyproject_content)
        end

        def sanitize_env_name(url)
          url.gsub(%r{^https?://}, "").gsub(/[^a-zA-Z0-9]/, "_").upcase
        end

        def declaration_regex(dep, old_req)
          # For UV, dependencies are in the [project] section
          /
            \[project\]\s*(?:\s*#.*?)*?\n.*?
            (?<declaration>
              (?:^\s*|["'])#{escape(dep.name)}["']?\s*=\s*["'].*?#{Regexp.escape(old_req[:requirement])}["']
            )
            .*$
          /mix
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
