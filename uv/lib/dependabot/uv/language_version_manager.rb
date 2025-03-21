# typed: strict
# frozen_string_literal: true

require "dependabot/logger"
require "dependabot/uv/version"
require "sorbet-runtime"

module Dependabot
  module Uv
    class LanguageVersionManager
      extend T::Sig

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
        @python_major_minor ||= T.let(T.must(Version.new(python_version).segments[0..1]).join("."), T.untyped)
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
          python_version_matching_imputed_requirements || Language::PRE_INSTALLED_HIGHEST_VERSION.to_s
        end
      end

      sig { params(requirement_string: T.nilable(String)).returns(T.nilable(String)) }
      def normalize_python_exact_version(requirement_string)
        return requirement_string if requirement_string.nil? || requirement_string.strip.empty?

        requirement_string = requirement_string.strip

        # If the requirement already has a wildcard, return nil
        return nil if requirement_string == "*"

        # If the requirement is not an exact version such as not X.Y.Z, =X.Y.Z, ==X.Y.Z, ===X.Y.Z
        # then return the requirement as is
        return requirement_string unless requirement_string.match?(/^=?={0,2}\s*\d+\.\d+(\.\d+)?(-[a-z0-9.-]+)?$/i)

        parts = requirement_string.gsub(/^=+/, "").split(".")

        case parts.length
        when 1 # Only major version (X)
          ">= #{parts[0]}.0.0 < #{parts[0].to_i + 1}.0.0" # Ensure only major version range
        when 2 # Major.Minor (X.Y)
          ">= #{parts[0]}.#{parts[1]}.0 < #{parts[0].to_i}.#{parts[1].to_i + 1}.0" # Ensure only minor version range
        when 3 # Major.Minor.Patch (X.Y.Z)
          ">= #{parts[0]}.#{parts[1]}.0 < #{parts[0].to_i}.#{parts[1].to_i + 1}.0" # Convert to >= X.Y.0
        else
          requirement_string
        end
      end

      sig { returns(String) }
      def python_version_from_supported_versions
        requirement_string = python_requirement_string

        # If the requirement string isn't already a range (eg ">3.10"), coerce it to "major.minor.*".
        # The patch version is ignored because a non-matching patch version is unlikely to affect resolution.
        requirement_string = requirement_string.gsub(/\.\d+$/, ".*") if /^\d/.match?(requirement_string)

        requirement_string = normalize_python_exact_version(requirement_string)

        if requirement_string.nil? || requirement_string.strip.empty?
          return Language::PRE_INSTALLED_HIGHEST_VERSION.to_s
        end

        # Try to match one of our pre-installed Python versions
        requirement = T.must(Requirement.requirements_array(requirement_string).first)
        version = Language::PRE_INSTALLED_PYTHON_VERSIONS.find { |v| requirement.satisfied_by?(v) }
        return version.to_s if version

        # Otherwise we have to raise an error
        supported_versions = Language::SUPPORTED_VERSIONS.map { |v| "#{v}.*" }.join(", ")
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
            Requirement.new(r)
          end
        python_version_matching(compiled_file_python_requirement_markers)
      end

      sig { params(requirements: T.untyped).returns(T.nilable(String)) }
      def python_version_matching(requirements)
        Language::PRE_INSTALLED_PYTHON_VERSIONS.find do |version|
          requirements.all? do |req|
            next req.any? { |r| r.satisfied_by?(version) } if req.is_a?(Array)

            req.satisfied_by?(version)
          end
        end.to_s
      end
    end
  end
end
