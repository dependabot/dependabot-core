# typed: strict
# frozen_string_literal: true

require "dependabot/logger"
require "dependabot/python/version"
require "sorbet-runtime"

module Dependabot
  module Python
    class LanguageVersionManager
      extend T::Sig
      # This list must match the versions specified at the top of `python/Dockerfile`
      PRE_INSTALLED_PYTHON_VERSIONS = %w(
        3.13.1
        3.12.7
        3.11.9
        3.10.15
        3.9.18
        3.8.20
      ).freeze

      sig { params(python_requirement_parser: T.untyped).void }
      def initialize(python_requirement_parser:)
        @python_requirement_parser = python_requirement_parser
      end

      sig { returns(T.nilable(String)) }
      def install_required_python
        # The leading space is important in the version check
        return if SharedHelpers.run_shell_command("pyenv versions").include?(" #{python_major_minor}.")

        SharedHelpers.run_shell_command(
          "tar -axf /usr/local/.pyenv/versions/#{python_version}.tar.zst -C /usr/local/.pyenv/versions"
        )
      end

      sig { returns(String) }
      def installed_version
        # Use `pyenv exec` to query the active Python version
        output, _status = SharedHelpers.run_shell_command("pyenv exec python --version")
        version = output.strip.split.last # Extract the version number (e.g., "3.13.1")

        T.must(version)
      end

      sig { returns(T.untyped) }
      def python_major_minor
        @python_major_minor ||= T.let(T.must(Python::Version.new(python_version).segments[0..1]).join("."), T.untyped)
      end

      sig { returns(String) }
      def python_version
        @python_version ||= T.let(python_version_from_supported_versions, T.nilable(String))
      end

      sig { returns(String) }
      def python_requirement_string
        if user_specified_python_version
          if user_specified_python_version.start_with?(/\d/)
            parts = user_specified_python_version.split(".")
            parts.fill("*", (parts.length)..2).join(".")
          else
            user_specified_python_version
          end
        else
          python_version_matching_imputed_requirements || PRE_INSTALLED_PYTHON_VERSIONS.first
        end
      end

      sig { returns(String) }
      def python_version_from_supported_versions
        requirement_string = python_requirement_string

        # If the requirement string isn't already a range (eg ">3.10"), coerce it to "major.minor.*".
        # The patch version is ignored because a non-matching patch version is unlikely to affect resolution.
        requirement_string = requirement_string.gsub(/\.\d+$/, ".*") if requirement_string.start_with?(/\d/)

        # Try to match one of our pre-installed Python versions
        requirement = T.must(Python::Requirement.requirements_array(requirement_string).first)
        version = PRE_INSTALLED_PYTHON_VERSIONS.find { |v| requirement.satisfied_by?(Python::Version.new(v)) }
        return version if version

        # Otherwise we have to raise
        supported_versions = PRE_INSTALLED_PYTHON_VERSIONS.map { |x| x.gsub(/\.\d+$/, ".*") }.join(", ")
        raise ToolVersionNotSupported.new("Python", python_requirement_string, supported_versions)
      end

      sig { returns(T.untyped) }
      def user_specified_python_version
        @python_requirement_parser.user_specified_requirements.first
      end

      sig { returns(T.nilable(String)) }
      def python_version_matching_imputed_requirements
        compiled_file_python_requirement_markers =
          @python_requirement_parser.imputed_requirements.map do |r|
            Dependabot::Python::Requirement.new(r)
          end
        python_version_matching(compiled_file_python_requirement_markers)
      end

      sig { params(requirements: T.untyped).returns(T.nilable(String)) }
      def python_version_matching(requirements)
        PRE_INSTALLED_PYTHON_VERSIONS.find do |version_string|
          version = Python::Version.new(version_string)
          requirements.all? do |req|
            next req.any? { |r| r.satisfied_by?(version) } if req.is_a?(Array)

            req.satisfied_by?(version)
          end
        end
      end
    end
  end
end
