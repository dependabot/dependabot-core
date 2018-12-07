# frozen_string_literal: true

require "excon"
require "toml-rb"

require "dependabot/python/file_parser"
require "dependabot/python/file_updater/pyproject_preparer"
require "dependabot/python/update_checker"
require "dependabot/shared_helpers"
require "dependabot/python/version"
require "dependabot/python/requirement"
require "dependabot/errors"
require "dependabot/python/native_helpers"
require "dependabot/python/python_versions"

module Dependabot
  module Python
    class UpdateChecker
      # This class does version resolution for pyproject.toml files.
      class PoetryVersionResolver
        VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/.freeze

        attr_reader :dependency, :dependency_files, :credentials

        def initialize(dependency:, dependency_files:, credentials:,
                       unlock_requirement:, latest_allowable_version:)
          @dependency               = dependency
          @dependency_files         = dependency_files
          @credentials              = credentials
          @latest_allowable_version = latest_allowable_version
          @unlock_requirement       = unlock_requirement

          check_private_sources_are_reachable
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
              write_temporary_dependency_files

              if python_version && !pre_installed_python?(python_version)
                run_poetry_command("pyenv install -s")
                run_poetry_command(
                  "pyenv exec pip install -r #{python_requirements_path}"
                )
              end

              # Shell out to Poetry, which handles everything for us.
              # Calling `lock` avoids doing an install.
              run_poetry_command("pyenv exec poetry lock")

              updated_lockfile =
                if File.exist?("poetry.lock") then File.read("poetry.lock")
                else File.read("pyproject.lock")
                end
              updated_lockfile = TomlRB.parse(updated_lockfile)

              fetch_version_from_parsed_lockfile(updated_lockfile)
            end
          return unless @latest_resolvable_version_string

          Python::Version.new(@latest_resolvable_version_string)
        end

        def fetch_version_from_parsed_lockfile(updated_lockfile)
          updated_lockfile.fetch("package", []).
            find { |d| d["name"] == dependency.name }.
            fetch("version")
        end

        def write_temporary_dependency_files(update_pyproject: true)
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          # Overwrite the .python-version with updated content
          File.write(".python-version", python_version) if python_version

          # Overwrite the pyproject with updated content
          if update_pyproject
            File.write("pyproject.toml", updated_pyproject_content)
          else
            File.write("pyproject.toml", sanitized_pyproject_content)
          end
        end

        def python_version
          pyproject_object = TomlRB.parse(pyproject.content)
          poetry_object = pyproject_object.dig("tool", "poetry")

          requirement =
            poetry_object&.dig("dependencies", "python") ||
            poetry_object&.dig("dev-dependencies", "python")

          return python_version_file&.content unless requirement

          requirements =
            Python::Requirement.requirements_array(requirement)

          PythonVersions::PYTHON_VERSIONS.find do |version|
            requirements.any? do |req|
              req.satisfied_by?(Python::Version.new(version))
            end
          end
        end

        def pre_installed_python?(version)
          PythonVersions::PRE_INSTALLED_PYTHON_VERSIONS.include?(version)
        end

        def updated_pyproject_content
          content = pyproject.content
          content = sanitize_pyproject_content(content)
          content = freeze_other_dependencies(content)
          content = unlock_target_dependency(content) if unlock_requirement?
          content
        end

        def sanitized_pyproject_content
          content = pyproject.content
          content = sanitize_pyproject_content(content)
          content
        end

        def sanitize_pyproject_content(pyproject_content)
          Python::FileUpdater::PyprojectPreparer.
            new(pyproject_content: pyproject_content).
            sanitize
        end

        def freeze_other_dependencies(pyproject_content)
          Python::FileUpdater::PyprojectPreparer.
            new(pyproject_content: pyproject_content).
            freeze_top_level_dependencies_except([dependency], lockfile)
        end

        def unlock_target_dependency(pyproject_content)
          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object.dig("tool", "poetry")

          %w(dependencies dev-dependencies).each do |type|
            names = poetry_object[type]&.keys || []
            pkg_name = names.find { |nm| normalise(nm) == dependency.name }
            next unless pkg_name

            if poetry_object.dig(type, pkg_name).is_a?(Hash)
              poetry_object[type][pkg_name]["version"] =
                updated_version_requirement_string
            else
              poetry_object[type][pkg_name] =
                updated_version_requirement_string
            end
          end

          TomlRB.dump(pyproject_object)
        end

        def check_private_sources_are_reachable
          sources_to_check =
            pyproject_sources +
            config_variable_sources

          sources_to_check.
            map { |details| details["url"] }.
            reject { |url| MAIN_PYPI_INDEXES.include?(url) }.
            each do |url|
              sanitized_url = url.gsub(%r{(?<=//).*(?=@)}, "redacted")

              response = Excon.get(
                url,
                idempotent: true,
                **SharedHelpers.excon_defaults
              )

              if response.status == 401 || response.status == 403
                raise PrivateSourceAuthenticationFailure, sanitized_url
              end
            rescue Excon::Error::Timeout, Excon::Error::Socket
              raise PrivateSourceTimedOut, sanitized_url
            end
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

        def pyproject
          dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        def pyproject_lock
          dependency_files.find { |f| f.name == "pyproject.lock" }
        end

        def poetry_lock
          dependency_files.find { |f| f.name == "poetry.lock" }
        end

        def lockfile
          poetry_lock || pyproject_lock
        end

        def python_version_file
          dependency_files.find { |f| f.name == ".python-version" }
        end

        def run_poetry_command(command)
          raw_response = nil
          IO.popen(command, err: %i(child out)) do |process|
            raw_response = process.read
          end

          # Raise an error with the output from the shell session if Pipenv
          # returns a non-zero status
          return if $CHILD_STATUS.success?

          raise SharedHelpers::HelperSubprocessFailed.new(
            raw_response,
            command
          )
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalise(name)
          name.downcase.gsub(/[-_.]+/, "-")
        end

        def config_variable_sources
          @config_variable_sources ||=
            credentials.
            select { |cred| cred["type"] == "python_index" }.
            map { |h| { "url" => h["index-url"].gsub(%r{/*$}, "") + "/" } }
        end

        def pyproject_sources
          sources =
            TomlRB.parse(pyproject.content).dig("tool", "poetry", "source") ||
            []

          @pyproject_sources ||=
            sources.
            map { |h| h.dup.merge("url" => h["url"].gsub(%r{/*$}, "") + "/") }
        end

        def python_requirements_path
          File.join(NativeHelpers.python_helper_path, "requirements.txt")
        end
      end
    end
  end
end
