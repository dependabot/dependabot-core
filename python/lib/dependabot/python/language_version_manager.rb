# frozen_string_literal: true

require "dependabot/logger"
require "dependabot/python/version"

module Dependabot
  module Python
    class LanguageVersionManager
      def initialize(python_requirement_parser:)
        @python_requirement_parser = python_requirement_parser
      end

      def install_required_python
        # The leading space is important in the version check
        return if SharedHelpers.run_shell_command("pyenv versions").include?(" #{python_major_minor}.")

        if File.exist?("/usr/local/.pyenv/#{python_major_minor}.tar.gz")
          SharedHelpers.run_shell_command(
            "tar xzf /usr/local/.pyenv/#{python_major_minor}.tar.gz -C /usr/local/.pyenv/"
          )
          return if SharedHelpers.run_shell_command("pyenv versions").
                    include?(" #{python_major_minor}.")
        end

        Dependabot.logger.info("Installing required Python #{python_version}.")
        start = Time.now
        SharedHelpers.run_shell_command("pyenv install -s #{python_version}")
        SharedHelpers.run_shell_command("pyenv exec pip install --upgrade pip")
        SharedHelpers.run_shell_command("pyenv exec pip install -r" \
                                        "#{NativeHelpers.python_requirements_path}")
        time_taken = Time.now - start
        Dependabot.logger.info("Installing Python #{python_version} took #{time_taken}s.")
      end

      def python_major_minor
        @python ||= Python::Version.new(python_version)
        "#{@python.segments[0]}.#{@python.segments[1]}"
      end

      def python_version
        @python_version ||= python_version_from_supported_versions
      end

      def python_requirement_string
        if user_specified_python_version
          if user_specified_python_version.start_with?(/\d/)
            parts = user_specified_python_version.split(".")
            parts.fill("*", (parts.length)..2).join(".")
          else
            user_specified_python_version
          end
        elsif python_version_matching_imputed_requirements
          python_version_matching_imputed_requirements
        else
          PythonVersions::PRE_INSTALLED_PYTHON_VERSIONS.first
        end
      end

      def python_version_from_supported_versions
        requirement_string = python_requirement_string

        # Ideally, the requirement is satisfied by a Python version we support
        requirement =
          Python::Requirement.requirements_array(requirement_string).first
        version =
          PythonVersions::SUPPORTED_VERSIONS_TO_ITERATE.
          find { |v| requirement.satisfied_by?(Python::Version.new(v)) }
        return version if version

        # If not, and we're dealing with a simple version string
        # and changing the patch version would fix things, we do that
        # as the patch version is unlikely to affect resolution
        if requirement_string.start_with?(/\d/)
          requirement =
            Python::Requirement.new(requirement_string.gsub(/\.\d+$/, ".*"))
          version =
            PythonVersions::SUPPORTED_VERSIONS_TO_ITERATE.
            find { |v| requirement.satisfied_by?(Python::Version.new(v)) }
          return version if version
        end

        # Otherwise we have to raise, giving details of the Python versions
        # that Dependabot supports
        msg = "Dependabot detected the following Python requirement " \
              "for your project: '#{requirement_string}'.\n\nCurrently, the " \
              "following Python versions are supported in Dependabot: " \
              "#{PythonVersions::SUPPORTED_VERSIONS.join(', ')}."
        raise DependencyFileNotResolvable, msg
      end

      def user_specified_python_version
        @python_requirement_parser.user_specified_requirements.first
      end

      def python_version_matching_imputed_requirements
        compiled_file_python_requirement_markers =
          @python_requirement_parser.imputed_requirements.map do |r|
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

      def pre_installed_python?(version)
        PythonVersions::PRE_INSTALLED_PYTHON_VERSIONS.include?(version)
      end
    end
  end
end
