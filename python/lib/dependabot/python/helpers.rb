# frozen_string_literal: true

require "dependabot/logger"
require "dependabot/python/version"

module Dependabot
  module Python
    module Helpers
      def self.install_required_python(dependency_files)
        # The leading space is important in the version check
        return if SharedHelpers.run_shell_command("pyenv versions").include?(" #{python_major_minor(dependency_files)}.")

        if File.exist?("/usr/local/.pyenv/#{python_major_minor(dependency_files)}.tar.gz")
          SharedHelpers.run_shell_command(
            "tar xzf /usr/local/.pyenv/#{python_major_minor(dependency_files)}.tar.gz -C /usr/local/.pyenv/"
          )
          return if SharedHelpers.run_shell_command("pyenv versions").
                    include?(" #{python_major_minor(dependency_files)}.")
        end

        Dependabot.logger.info("Installing required Python #{python_version(dependency_files)}.")
        start = Time.now
        SharedHelpers.run_shell_command("pyenv install -s #{python_version(dependency_files)}")
        SharedHelpers.run_shell_command("pyenv exec pip install --upgrade pip")
        SharedHelpers.run_shell_command("pyenv exec pip install -r" \
                                        "#{NativeHelpers.python_requirements_path}")
        time_taken = Time.now - start
        Dependabot.logger.info("Installing Python #{python_version(dependency_files)} took #{time_taken}s.")
      end

      def self.python_major_minor(dependency_files)
        @python ||= Python::Version.new(python_version(dependency_files))
        "#{@python.segments[0]}.#{@python.segments[1]}"
      end

      def self.python_version(dependency_files)
        requirements = python_requirement_parser(dependency_files).user_specified_requirements
        requirements = requirements.
                       map { |r| Python::Requirement.requirements_array(r) }

        @python_version ||= PythonVersions::SUPPORTED_VERSIONS_TO_ITERATE.find do |version|
          requirements.all? do |reqs|
            reqs.any? { |r| r.satisfied_by?(Python::Version.new(version)) }
          end
        end

      end

      def self.python_requirement_parser(dependency_files)
        @python_requirement_parser ||=
          FileParser::PythonRequirementParser.new(
            dependency_files: dependency_files
          )
      end
    end
  end
end
