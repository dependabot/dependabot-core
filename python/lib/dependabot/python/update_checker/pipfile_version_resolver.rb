# frozen_string_literal: true

require "excon"
require "toml-rb"

require "dependabot/python/file_parser"
require "dependabot/python/file_updater/pipfile_preparer"
require "dependabot/python/file_updater/setup_file_sanitizer"
require "dependabot/python/update_checker"
require "dependabot/shared_helpers"
require "dependabot/utils/python/version"
require "dependabot/errors"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module Python
    class UpdateChecker
      # This class does version resolution for Pipfiles. Its current approach
      # is somewhat crude:
      # - Unlock the dependency we're checking in the Pipfile
      # - Freeze all of the other dependencies in the Pipfile
      # - Run `pipenv lock` and see what the result is
      #
      # Unfortunately, Pipenv doesn't resolve how we'd expect - it appears to
      # just raise if the latest version can't be resolved. Knowing that is
      # still better than nothing, though.
      class PipfileVersionResolver
        VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/.freeze
        GIT_DEPENDENCY_UNREACHABLE_REGEX =
          /Command "git clone -q (?<url>[^\s]+).*" failed/.freeze
        GIT_REFERENCE_NOT_FOUND_REGEX =
          %r{"git checkout -q (?<tag>[^"]+)" .*/(?<name>.*?)(\\n'\]|$)}.
          freeze
        UNSUPPORTED_DEPS = %w(pyobjc).freeze
        UNSUPPORTED_DEP_REGEX =
          /"python setup\.py egg_info".*(?:#{UNSUPPORTED_DEPS.join("|")})/.
          freeze

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
              SharedHelpers.with_git_configured(credentials: credentials) do
                write_temporary_dependency_files

                # Shell out to Pipenv, which handles everything for us.
                # Whilst calling `lock` avoids doing an install as part of the
                # pipenv flow, an install is still done by pip-tools in order
                # to resolve the dependencies. That means this is slow.
                run_pipenv_command(
                  pipenv_environment_variables + "pyenv exec pipenv lock"
                )

                updated_lockfile = JSON.parse(File.read("Pipfile.lock"))

                fetch_version_from_parsed_lockfile(updated_lockfile)
              end
            rescue SharedHelpers::HelperSubprocessFailed => error
              handle_pipenv_errors(error)
            end
          return unless @latest_resolvable_version_string

          Utils::Python::Version.new(@latest_resolvable_version_string)
        end

        def fetch_version_from_parsed_lockfile(updated_lockfile)
          if dependency.requirements.any?
            group = dependency.requirements.first[:groups].first
            deps = updated_lockfile[group] || {}

            version =
              deps.transform_keys { |k| normalise(k) }.
              dig(dependency.name, "version")&.
              gsub(/^==/, "")

            return version
          end

          FileParsers::Python::Pip::DEPENDENCY_GROUP_KEYS.each do |keys|
            deps = updated_lockfile[keys.fetch(:lockfile)] || {}
            version =
              deps.transform_keys { |k| normalise(k) }.
              dig(dependency.name, "version")&.
              gsub(/^==/, "")

            return version if version
          end

          # If the sub-dependency no longer appears in the lockfile return nil
          nil
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        def handle_pipenv_errors(error)
          if error.message.include?("no version found at all") ||
             error.message.include?("Invalid specifier:") ||
             error.message.include?("Max retries exceeded")
            msg = clean_error_message(error.message)
            raise if msg.empty?

            raise DependencyFileNotResolvable, msg
          end

          if error.message.match?(UNSUPPORTED_DEP_REGEX)
            msg = "Dependabot detected a dependency that can't be built on "\
                  "linux. Currently, all Dependabot builds happen on linux "\
                  "boxes, so there is no way for Dependabot to resolve your "\
                  "dependency files.\n\n"\
                  "Unless you think Dependabot has made a mistake (please "\
                  "tag us if so) you may wish to disable Dependabot on this "\
                  "repo."
            raise DependencyFileNotResolvable, msg
          end

          if error.message.include?("Could not find a version") ||
             error.message.include?("is not a python version")
            check_original_requirements_resolvable
          end

          if error.message.include?('Command "python setup.py egg_info"') &&
             error.message.include?(dependency.name)
            # The latest version of the dependency we're updating is borked
            # (because it has an unevaluatable setup.py). Skip the update.
            return nil
          end

          if error.message.match?(GIT_DEPENDENCY_UNREACHABLE_REGEX)
            url = error.message.match(GIT_DEPENDENCY_UNREACHABLE_REGEX).
                  named_captures.fetch("url")
            raise GitDependenciesNotReachable, url
          end

          if error.message.match?(GIT_REFERENCE_NOT_FOUND_REGEX)
            name = error.message.match(GIT_REFERENCE_NOT_FOUND_REGEX).
                   named_captures.fetch("name")
            raise GitDependencyReferenceNotFound, name
          end

          raise unless error.message.include?("could not be resolved")
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        # Needed because Pipenv's resolver isn't perfect.
        # Note: We raise errors from this method, rather than returning a
        # boolean, so that all deps for this repo will raise identical
        # errors when failing to update
        def check_original_requirements_resolvable
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_temporary_dependency_files(update_pipfile: false)

              run_pipenv_command(
                pipenv_environment_variables + "pyenv exec pipenv lock"
              )

              true
            rescue SharedHelpers::HelperSubprocessFailed => error
              if error.message.include?("Could not find a version")
                msg = clean_error_message(error.message)
                msg.gsub!(/\s+\(from .*$/, "")
                raise if msg.empty?

                raise DependencyFileNotResolvable, msg
              end

              if error.message.include?("is not a python version")
                msg = "Pipenv does not support specifying Python ranges "\
                  "(see https://github.com/pypa/pipenv/issues/1050 for more "\
                  "details)."
                raise DependencyFileNotResolvable, msg
              end

              raise
            end
          end
        end

        def clean_error_message(message)
          # Pipenv outputs a lot of things to STDERR, so we need to clean
          # up the error message
          msg_lines = message.lines
          msg = msg_lines.
                take_while { |l| !l.start_with?("During handling of") }.
                drop_while do |l|
                  next false if l.start_with?("CRITICAL:")
                  next false if l.start_with?("ERROR:")
                  next false if l.start_with?("packaging.specifiers")
                  next false if l.include?("Max retries exceeded")

                  true
                end.join.strip

          # We also need to redact any URLs, as they may include credentials
          msg.gsub(/http.*?(?=\s)/, "<redacted>")
        end

        def write_temporary_dependency_files(update_pipfile: true)
          dependency_files.each do |file|
            next if file.name == ".python-version"

            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

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
          File.write(
            "Pipfile",
            pipfile_content(update_pipfile: update_pipfile)
          )
        end

        def sanitized_setup_file_content(file)
          @sanitized_setup_file_content ||= {}
          @sanitized_setup_file_content[file.name] ||=
            FileUpdaters::Python::Pip::SetupFileSanitizer.
            new(setup_file: file, setup_cfg: setup_cfg(file)).
            sanitized_content
        end

        def setup_cfg(file)
          config_name = file.name.sub(/\.py$/, ".cfg")
          dependency_files.find { |f| f.name == config_name }
        end

        def pipfile_content(update_pipfile: true)
          content = pipfile.content
          return content unless update_pipfile

          content = freeze_other_dependencies(content)
          content = unlock_target_dependency(content) if unlock_requirement?
          content = add_private_sources(content)
          content
        end

        def freeze_other_dependencies(pipfile_content)
          FileUpdaters::Python::Pip::PipfilePreparer.
            new(pipfile_content: pipfile_content).
            freeze_top_level_dependencies_except([dependency], lockfile)
        end

        def unlock_target_dependency(pipfile_content)
          pipfile_object = TomlRB.parse(pipfile_content)

          %w(packages dev-packages).each do |type|
            names = pipfile_object[type]&.keys || []
            pkg_name = names.find { |nm| normalise(nm) == dependency.name }
            next unless pkg_name

            if pipfile_object.dig(type, pkg_name).is_a?(Hash)
              pipfile_object[type][pkg_name]["version"] =
                updated_version_requirement_string
            else
              pipfile_object[type][pkg_name] =
                updated_version_requirement_string
            end
          end

          TomlRB.dump(pipfile_object)
        end

        def add_private_sources(pipfile_content)
          FileUpdaters::Python::Pip::PipfilePreparer.
            new(pipfile_content: pipfile_content).
            replace_sources(credentials)
        end

        def add_python_two_requirement_to_pipfile
          content = File.read("Pipfile")

          updated_content =
            FileUpdaters::Python::Pip::PipfilePreparer.
            new(pipfile_content: content).
            update_python_requirement("2.7.15")

          File.write("Pipfile", updated_content)
        end

        def pipfile_python_requirement
          parsed_pipfile = TomlRB.parse(pipfile.content)

          parsed_pipfile.dig("requires", "python_full_version") ||
            parsed_pipfile.dig("requires", "python_version")
        end

        def python_requirement_specified?
          return true if pipfile_python_requirement

          !python_version_file.nil?
        end

        def set_up_python_environment
          # Initialize a git repo to appease pip-tools
          begin
            SharedHelpers.run_shell_command("git init") if setup_files.any?
          rescue Dependabot::SharedHelpers::HelperSubprocessFailed
            nil
          end

          SharedHelpers.run_shell_command(
            "pyenv install -s #{python_version}"
          )
          SharedHelpers.run_shell_command("pyenv local #{python_version}")
          return if pre_installed_python?(python_version)

          SharedHelpers.run_shell_command(
            "pyenv exec pip install -r #{python_requirements_path}"
          )
        end

        def python_version
          requirement =
            if @using_python_two
              "2.7.*"
            elsif pipfile_python_requirement&.match?(/^\d/)
              parts = pipfile_python_requirement.split(".")
              parts.fill("*", (parts.length)..2).join(".")
            elsif python_version_file
              python_version_file.content
            else
              PythonVersions::PRE_INSTALLED_PYTHON_VERSIONS.first
            end

          requirement = Utils::Python::Requirement.new(requirement)

          PythonVersions::PYTHON_VERSIONS.find do |version|
            requirement.satisfied_by?(Utils::Python::Version.new(version))
          end
        end

        def pre_installed_python?(version)
          PythonVersions::PRE_INSTALLED_PYTHON_VERSIONS.include?(version)
        end

        def check_private_sources_are_reachable
          env_sources = pipfile_sources.select { |h| h["url"].include?("${") }

          check_env_sources_included_in_config_variables(env_sources)

          sources_to_check =
            pipfile_sources.reject { |h| h["url"].include?("${") } +
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
          unless Utils::Python::Version.correct?(latest_allowable_version)
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

        def run_pipenv_command(cmd)
          set_up_python_environment

          raw_response = nil
          IO.popen(cmd, err: %i(child out)) { |p| raw_response = p.read }

          # Raise an error with the output from the shell session if Pipenv
          # returns a non-zero status
          return if $CHILD_STATUS.success?

          raise SharedHelpers::HelperSubprocessFailed.new(raw_response, cmd)
        rescue SharedHelpers::HelperSubprocessFailed => error
          original_error ||= error
          msg = error.message

          relevant_error =
            if may_be_using_wrong_python_version?(msg) then original_error
            else error
            end

          raise relevant_error unless may_be_using_wrong_python_version?(msg)
          raise relevant_error if @using_python_two

          @using_python_two = true
          add_python_two_requirement_to_pipfile
          cmd = cmd.gsub("pipenv ", "pipenv --two ")
          retry
        ensure
          @using_python_two = nil
        end

        def may_be_using_wrong_python_version?(error_message)
          return false if python_requirement_specified?
          return true if error_message.include?("UnsupportedPythonVersion")

          error_message.include?('Command "python setup.py egg_info" failed')
        end

        def check_env_sources_included_in_config_variables(env_sources)
          config_variable_source_urls =
            config_variable_sources.map { |s| s["url"] }

          env_sources.each do |source|
            url = source["url"]
            known_parts = url.split(/\$\{.*?\}/).reject(&:empty?).compact

            # If the whole URL is an environment variable we can't do a check
            next if known_parts.none?

            regex = known_parts.map { |p| Regexp.quote(p) }.join(".*?")
            next if config_variable_source_urls.any? { |s| s.match?(regex) }

            raise PrivateSourceAuthenticationFailure, url
          end
        end

        def config_variable_sources
          @config_variable_sources ||=
            credentials.
            select { |cred| cred["type"] == "python_index" }.
            map { |h| { "url" => h["index-url"].gsub(%r{/*$}, "") + "/" } }
        end

        def pipfile_sources
          @pipfile_sources ||=
            TomlRB.parse(pipfile.content).fetch("source", []).
            map { |h| h.dup.merge("url" => h["url"].gsub(%r{/*$}, "") + "/") }
        end

        def pipenv_environment_variables
          environment_variables = [
            "PIPENV_YES=true",       # Install new Python versions if needed
            "PIPENV_MAX_RETRIES=3",  # Retry timeouts
            "PIPENV_NOSPIN=1",       # Don't pollute logs with spinner
            "PIPENV_TIMEOUT=600",    # Set install timeout to 10 minutes
            "PIP_DEFAULT_TIMEOUT=60" # Set pip timeout to 1 minute
          ]

          environment_variables.join(" ") + " "
        end

        def python_requirements_path
          project_root = File.join(File.dirname(__FILE__), "../../../../..")
          File.join(project_root, "helpers/python/requirements.txt")
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalise(name)
          name.downcase.gsub(/[-_.]+/, "-")
        end

        def pipfile
          dependency_files.find { |f| f.name == "Pipfile" }
        end

        def lockfile
          dependency_files.find { |f| f.name == "Pipfile.lock" }
        end

        def setup_files
          dependency_files.select { |f| f.name.end_with?("setup.py") }
        end

        def setup_cfg_files
          dependency_files.select { |f| f.name.end_with?("setup.cfg") }
        end

        def python_version_file
          dependency_files.find { |f| f.name == ".python-version" }
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
