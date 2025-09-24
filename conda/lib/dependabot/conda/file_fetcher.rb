# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/conda/python_package_classifier"

module Dependabot
  module Conda
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      ENVIRONMENT_FILE_NAMES = T.let(
        %w(
          environment.yml
          environment.yaml
        ).freeze,
        T::Array[String]
      )

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |filename| ENVIRONMENT_FILE_NAMES.include?(filename) }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain an environment.yml or environment.yaml file."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        []
      end

      private

      # Check if an environment file contains Python packages we can manage
      sig { params(file: DependencyFile).returns(T::Boolean) }
      def environment_contains_manageable_packages?(file)
        content = file.content
        return false unless content

        parsed_yaml = begin
          parse_yaml_content(content)
        rescue Psych::SyntaxError => e
          Dependabot.logger.error("YAML parsing error: #{e.message}")
          nil
        end
        return false unless parsed_yaml

        manageable_conda_packages?(parsed_yaml) || manageable_pip_packages?(parsed_yaml)
      end

      # Parse YAML content and return parsed hash or nil
      sig { params(content: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def parse_yaml_content(content)
        require "yaml"
        parsed = YAML.safe_load(content)
        parsed.is_a?(Hash) ? parsed : nil
      end

      # Check if the parsed YAML contains manageable conda packages
      sig { params(parsed_yaml: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
      def manageable_conda_packages?(parsed_yaml)
        dependencies = parsed_yaml["dependencies"]
        return false unless dependencies.is_a?(Array)

        simplified_packages = dependencies.select do |dep|
          dep.is_a?(String) && !fully_qualified_spec?(dep) &&
            PythonPackageClassifier.python_package?(PythonPackageClassifier.extract_package_name(dep))
        end
        simplified_packages.any?
      end

      # Check if the parsed YAML contains manageable pip packages
      sig { params(parsed_yaml: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
      def manageable_pip_packages?(parsed_yaml)
        dependencies = parsed_yaml["dependencies"]
        return false unless dependencies.is_a?(Array)

        pip_deps = dependencies.find { |dep| dep.is_a?(Hash) && dep.key?("pip") }
        return false unless pip_deps && pip_deps["pip"].is_a?(Array)

        python_pip_packages = pip_deps["pip"].select do |pip_dep|
          pip_dep.is_a?(String) &&
            PythonPackageClassifier.python_package?(PythonPackageClassifier.extract_package_name(pip_dep))
        end
        python_pip_packages.any?
      end

      # Check if a package specification is fully qualified (build string included)
      sig { params(spec: String).returns(T::Boolean) }
      def fully_qualified_spec?(spec)
        # Fully qualified specs have format: package=version=build_string
        # e.g., "numpy=1.21.0=py39h20f2e39_0"
        parts = spec.split("=")
        return false unless parts.length >= 3

        build_string = parts[2]
        return false unless build_string

        build_string.match?(/^[a-zA-Z0-9_]+$/)
      end

      sig { returns(String) }
      def unsupported_environment_message
        <<~MSG
          This Conda environment file is not currently supported by Dependabot.

          Dependabot-Conda supports Python packages only and requires one of the following:

          1. **Simplified conda specifications**: Dependencies using simple version syntax (e.g., numpy=1.21.0)
          2. **Pip section with Python packages**: A 'pip:' section containing Python packages from PyPI

          **Not supported:**
          - Fully qualified conda specifications (e.g., numpy=1.21.0=py39h20f2e39_0)
          - Non-Python packages (R packages, system tools, etc.)
          - Environments without any Python packages

          To make your environment compatible:
          - Use simplified conda package specifications for conda packages
          - Add a pip section for PyPI packages
          - Focus on Python packages only

          For more information, see the Dependabot-Conda documentation.
        MSG
      end
    end
  end
end

Dependabot::FileFetchers.register("conda", Dependabot::Conda::FileFetcher)
