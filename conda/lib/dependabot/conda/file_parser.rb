# typed: strict
# frozen_string_literal: true

require "yaml"
require "sorbet-runtime"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/conda/python_package_classifier"
require "dependabot/conda/requirement"
require "dependabot/conda/version"
require "dependabot/conda/package_manager"

module Dependabot
  module Conda
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependencies = T.let([], T::Array[Dependabot::Dependency])

        environment_files.each do |file|
          dependencies.concat(parse_environment_file(file))
        end

        dependencies.uniq
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: nil
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          CondaPackageManager.new,
          T.nilable(Ecosystem::VersionManager)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def environment_files
        dependency_files.select { |f| f.name.match?(/^environment\.ya?ml$/i) }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_environment_file(file)
        dependencies = T.let([], T::Array[Dependabot::Dependency])

        begin
          content = file.content || ""
          parsed_yaml = YAML.safe_load(content)
          return dependencies unless parsed_yaml.is_a?(Hash)

          # Parse main dependencies (conda packages)
          if parsed_yaml["dependencies"].is_a?(Array)
            dependencies.concat(parse_conda_dependencies(parsed_yaml["dependencies"], file))
          end

          # Parse pip dependencies if present
          pip_deps = find_pip_dependencies(parsed_yaml["dependencies"])
          dependencies.concat(parse_pip_dependencies(pip_deps, file)) if pip_deps
        rescue Psych::SyntaxError, Psych::DisallowedClass => e
          raise Dependabot::DependencyFileNotParseable, "Invalid YAML in #{file.name}: #{e.message}"
        end

        dependencies
      end

      sig do
        params(dependencies: T::Array[T.untyped],
               file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency])
      end
      def parse_conda_dependencies(dependencies, file)
        parsed_dependencies = T.let([], T::Array[Dependabot::Dependency])

        # Check if environment has fully qualified packages (Tier 2)
        has_fully_qualified = dependencies.any? do |dep|
          dep.is_a?(String) && fully_qualified_package?(dep)
        end

        dependencies.each do |dep|
          next unless dep.is_a?(String)
          next if dep.is_a?(Hash) # Skip pip section

          # Skip conda dependencies if we have fully qualified packages (Tier 2 support)
          next if has_fully_qualified

          parsed_dep = parse_conda_dependency_string(dep, file)
          next unless parsed_dep
          next unless python_package?(parsed_dep[:name])
          next if parsed_dep[:name] == "pip" # Skip pip itself as it's infrastructure

          parsed_dependencies << create_dependency(
            name: parsed_dep[:name],
            version: parsed_dep[:version],
            requirements: parsed_dep[:requirements],
            package_manager: "conda"
          )
        end

        parsed_dependencies
      end

      sig { params(dependencies: T.nilable(T::Array[T.untyped])).returns(T.nilable(T::Array[String])) }
      def find_pip_dependencies(dependencies)
        return nil unless dependencies.is_a?(Array)

        pip_section = dependencies.find { |dep| dep.is_a?(Hash) && dep["pip"] }
        return nil unless pip_section

        pip_deps = pip_section["pip"]
        pip_deps.is_a?(Array) ? pip_deps : nil
      end

      sig do
        params(pip_deps: T::Array[String], file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency])
      end
      def parse_pip_dependencies(pip_deps, file)
        parsed_dependencies = T.let([], T::Array[Dependabot::Dependency])

        pip_deps.each do |dep|
          next unless dep.is_a?(String)

          parsed_dep = parse_pip_dependency_string(dep, file)
          next unless parsed_dep

          parsed_dependencies << create_dependency(
            name: parsed_dep[:name],
            version: parsed_dep[:version],
            requirements: parsed_dep[:requirements],
            package_manager: "conda"
          )
        end

        parsed_dependencies
      end

      sig do
        params(dep_string: String, file: Dependabot::DependencyFile).returns(T.nilable(T::Hash[Symbol, T.untyped]))
      end
      def parse_conda_dependency_string(dep_string, file)
        return nil if dep_string.nil?

        # Handle channel specifications: conda-forge::numpy=1.21.0
        normalized_dep_string = normalize_conda_dependency_string(dep_string)
        return nil if normalized_dep_string.nil?

        # Parse conda-style version specifications
        # Examples: numpy=1.21.0, scipy>=1.7.0, pandas, python=3.9, python>=3.8,<3.11
        match = normalized_dep_string.match(/^([a-zA-Z0-9_.-]+)(?:\s*(.+))?$/)
        return nil unless match

        name = match[1]
        constraint = match[2]&.strip

        version = extract_conda_version(constraint)
        requirements = build_conda_requirements(constraint, file)

        {
          name: name,
          version: version,
          requirements: requirements
        }
      end

      sig { params(dep_string: String).returns(T.nilable(String)) }
      def normalize_conda_dependency_string(dep_string)
        return dep_string unless dep_string.include?("::")

        parts = dep_string.split("::", 2)
        parts[1]
      end

      sig { params(constraint: T.nilable(String)).returns(T.nilable(String)) }
      def extract_conda_version(constraint)
        return nil unless constraint

        case constraint
        when /^=([0-9][a-zA-Z0-9._+-]+)$/
          # Exact conda version: =1.26.0
          constraint[1..-1] # Remove the = prefix
        when /^>=([0-9][a-zA-Z0-9._+-]+)$/
          # Minimum version constraint: >=1.26.0
          # For security purposes, treat this as the current version
          constraint[2..-1] # Remove the >= prefix
        when /^~=([0-9][a-zA-Z0-9._+-]+)$/
          # Compatible release: ~=1.26.0
          constraint[2..-1] # Remove the ~= prefix
        end
      end

      sig do
        params(constraint: T.nilable(String),
               file: Dependabot::DependencyFile).returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def build_conda_requirements(constraint, file)
        return [] unless constraint && !constraint.empty?

        [{
          requirement: constraint,
          file: file.name,
          source: nil,
          groups: ["dependencies"]
        }]
      end

      sig do
        params(dep_string: String, file: Dependabot::DependencyFile).returns(T.nilable(T::Hash[Symbol, T.untyped]))
      end
      def parse_pip_dependency_string(dep_string, file)
        # Handle pip-style specifications: requests==2.25.1, flask>=1.0.0
        match = dep_string.match(/^([a-zA-Z0-9_.-]+)(?:\s*(==|>=|>|<=|<|!=|~=)\s*([0-9][a-zA-Z0-9._+-]*))?$/)
        return nil unless match

        name = match[1]
        operator = match[2]
        version = match[3]

        # Extract meaningful version information for security update purposes
        extracted_version = nil
        if version
          case operator
          when "==", "="
            # Exact version: use as-is
            extracted_version = version
          when ">=", "~="
            # Minimum version constraint: use the specified version as current
            # This allows security updates to work by treating the constraint as current version
            extracted_version = version
          when ">"
            # Greater than: we can't determine exact version, leave as nil
            extracted_version = nil
          when "<=", "<", "!="
            # Upper bounds or exclusions: not useful for determining current version
            extracted_version = nil
          end
        end

        requirements = if operator && version
                         [{
                           requirement: "#{operator}#{version}",
                           file: file.name,
                           source: nil,
                           groups: ["pip"]
                         }]
                       else
                         []
                       end

        {
          name: name,
          version: extracted_version,
          requirements: requirements
        }
      end

      sig do
        params(
          name: String,
          version: T.nilable(String),
          requirements: T::Array[T::Hash[Symbol, T.untyped]],
          package_manager: String
        ).returns(Dependabot::Dependency)
      end
      def create_dependency(name:, version:, requirements:, package_manager:)
        Dependabot::Dependency.new(
          name: name,
          version: version,
          requirements: requirements,
          package_manager: package_manager
        )
      end

      sig { params(package_name: String).returns(T::Boolean) }
      def python_package?(package_name)
        PythonPackageClassifier.python_package?(package_name)
      end

      sig { params(dep_string: String).returns(T::Boolean) }
      def fully_qualified_package?(dep_string)
        # Fully qualified packages have build strings after the version
        # Format: package=version=build_string
        # Example: python=3.9.7=h60c2a47_0_cpython
        dep_string.count("=") >= 2
      end

      sig { override.returns(T::Boolean) }
      def check_required_files
        dependency_files.any? { |f| f.name.match?(/^environment\.ya?ml$/i) }
      end
    end
  end
end

Dependabot::FileParsers.register("conda", Dependabot::Conda::FileParser)
