# frozen_string_literal: true

require "dependabot/logger"
require "dependabot/python/version"

module Dependabot
  module Python
    module Helpers
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
        requirements = python_requirement_parser.user_specified_requirements
        requirements = requirements.
                       map { |r| Python::Requirement.requirements_array(r) }

        @python_version ||= PythonVersions::SUPPORTED_VERSIONS_TO_ITERATE.find do |version|
          requirements.all? do |reqs|
            reqs.any? { |r| r.satisfied_by?(Python::Version.new(version)) }
          end
        end

      end

      def python_requirement_parser
        @python_requirement_parser ||=
          FileParser::PythonRequirementParser.new(
            dependency_files: dependency_files
          )
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
          FileParser::PythonRequirementParser.
          new(dependency_files: dependency_files)
      end
    end
  end
end
