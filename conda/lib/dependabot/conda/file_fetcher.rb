# typed: strict
# frozen_string_literal: true

require "yaml"
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
          validation = validate_conda_environment(environment_file)
          unless validation[:valid]
            raise(
              Dependabot::DependencyFileNotFound.new(
                File.join(directory, environment_file.name),
                unsupported_environment_message(validation[:reason])
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
      # Returns a hash with :valid (Boolean) and :reason (Symbol or nil)
      sig { params(file: DependencyFile).returns(T::Hash[Symbol, T.untyped]) }
      def validate_conda_environment(file)
        content = file.content
        return { valid: false, reason: :no_content } unless content

        parsed_yaml = parse_and_validate_yaml(content)
        return { valid: false, reason: :invalid_yaml } unless parsed_yaml

        dependencies = parsed_yaml["dependencies"]
        return { valid: false, reason: :no_dependencies } unless dependencies.is_a?(Array)
        return { valid: false, reason: :empty_dependencies } if dependencies.empty?

        # Check if all packages are fully qualified (no manageable packages)
        return { valid: false, reason: :all_fully_qualified } unless manageable_packages?(dependencies)

        { valid: true, reason: nil }
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

      sig { params(reason: T.nilable(Symbol)).returns(String) }
      def unsupported_environment_message(reason)
        case reason
        when :all_fully_qualified
          <<~MSG
            This environment file contains only fully qualified package specifications with build strings.

            Dependabot cannot update packages with build strings like:
              - numpy=1.21.0=py39h20f2e39_0

            To fix, remove the build string. Dependabot supports simplified specifications \
            (e.g., numpy=1.21.0,r-base>=4.0)
          MSG
        when :no_dependencies, :empty_dependencies
          <<~MSG
            This environment file has no dependencies to manage.

            Add at least one package to the dependencies section:
              dependencies:
                - python>=3.9
                - numpy>=1.21.0
          MSG
        when :invalid_yaml
          <<~MSG
            This environment file contains invalid YAML syntax.

            Please fix the YAML syntax errors before Dependabot can process this file.
          MSG
        else
          <<~MSG
            This Conda environment file is not supported by Dependabot.

            Dependabot supports:
            - Simplified conda specifications (e.g., numpy=1.21.0, r-base>=4.0)
            - Pip dependencies in the pip section

            Not supported:
            - Fully qualified specifications with build strings (e.g., numpy=1.21.0=py39h20f2e39_0)
          MSG
        end
      end
    end
  end
end

Dependabot::FileFetchers.register("conda", Dependabot::Conda::FileFetcher)
