# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

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
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Conda support is currently in beta. Set ALLOW_BETA_ECOSYSTEMS=true to enable it."
          )
        end

        fetched_files = []

        # Try to fetch environment.yml first, then environment.yaml
        environment_file = fetch_file_if_present("environment.yml") ||
                           fetch_file_if_present("environment.yaml")

        if environment_file
          # Validate it's a proper conda environment file
          unless valid_conda_environment?(environment_file)
            raise(
              Dependabot::DependencyFileNotFound.new(
                File.join(directory, environment_file.name),
                unsupported_environment_message
              )
            )
          end
          fetched_files << environment_file
        end

        return fetched_files if fetched_files.any?

        raise(
          Dependabot::DependencyFileNotFound,
          File.join(directory, "environment.yml")
        )
      end

      private

      # Validate that environment file is a proper conda manifest with manageable packages
      sig { params(file: DependencyFile).returns(T::Boolean) }
      def valid_conda_environment?(file)
        content = file.content
        return false unless content

        parsed_yaml = parse_and_validate_yaml(content)
        return false unless parsed_yaml

        dependencies = parsed_yaml["dependencies"]
        return false unless valid_dependencies_section?(dependencies)

        manageable_packages?(dependencies)
      end

      sig { params(content: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def parse_and_validate_yaml(content)
        parsed_yaml = parse_yaml_content(content)
        return nil unless parsed_yaml
        return nil unless parsed_yaml.is_a?(Hash)

        parsed_yaml
      rescue Psych::SyntaxError => e
        Dependabot.logger.error("YAML parsing error: #{e.message}")
        nil
      end

      sig { params(dependencies: T.untyped).returns(T::Boolean) }
      def valid_dependencies_section?(dependencies)
        !!(dependencies.is_a?(Array) && !dependencies.empty? && manageable_packages?(dependencies))
      end

      # Check if there are any manageable packages (simple specs or pip)
      sig { params(dependencies: T.untyped).returns(T::Boolean) }
      def manageable_packages?(dependencies)
        return false unless dependencies.is_a?(Array)

        has_simple_conda = dependencies.any? do |dep|
          dep.is_a?(String) && !fully_qualified_spec?(dep)
        end

        has_pip = dependencies.any? { |dep| dep.is_a?(Hash) && dep.key?("pip") }

        has_simple_conda || has_pip
      end

      sig { params(content: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def parse_yaml_content(content)
        require "yaml"
        parsed = YAML.safe_load(content)
        parsed.is_a?(Hash) ? parsed : nil
      end

      sig { params(spec: String).returns(T::Boolean) }
      def fully_qualified_spec?(spec)
        # Fully qualified: package=version=build_string (e.g., numpy=1.21.0=py39h20f2e39_0)
        return false if spec.include?("==")
        return false if spec.include?("[")

        parts = spec.split("=")
        return false unless parts.length >= 3

        build_string = parts[2]
        return false unless build_string && !build_string.empty?

        build_string.match?(/^[a-zA-Z0-9_]+$/)
      end

      sig { returns(String) }
      def unsupported_environment_message
        <<~MSG
          This Conda environment file is not currently supported by Dependabot.

          Dependabot-Conda supports all package types from public Conda channels.

          **Supported:**
          - Simplified conda specifications (e.g., numpy=1.21.0, r-base>=4.0)
          - All package types: Python, R, Julia, system tools, etc.
          - Pip dependencies in pip section
          - Public channels: anaconda, conda-forge, bioconda, defaults

          **Not supported:**
          - Fully qualified conda specifications (e.g., numpy=1.21.0=py39h20f2e39_0)
          - Private channels requiring authentication

          To make your environment compatible:
          - Use simplified package specifications (no build strings)
          - Use public Conda channels

          For more information, see the Dependabot-Conda documentation.
        MSG
      end
    end
  end
end

Dependabot::FileFetchers.register("conda", Dependabot::Conda::FileFetcher)
