# typed: strict
# frozen_string_literal: true

require "yaml"
require "sorbet-runtime"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/conda/requirement"

module Dependabot
  module Conda
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      ENVIRONMENT_REGEX = /^environment\.ya?ml$/i

      # Common version constraint pattern for conda and pip dependencies
      VERSION_CONSTRAINT_PATTERN = '(\s*[=<>!~]=?\s*[^#\s]\S*(?:\s*,\s*[=<>!~]=?\s*[^#\s]\S*)*)?'

      # Regex patterns for dependency matching
      CONDA_CHANNEL_PATTERN = lambda do |name|
        /^(\s{2,4}-\s+[a-zA-Z0-9_.-]+::)(#{Regexp.escape(name)})#{VERSION_CONSTRAINT_PATTERN}(\s*)(#.*)?$/
      end

      CONDA_SIMPLE_PATTERN = lambda do |name|
        /^(\s{2,4}-\s+)(#{Regexp.escape(name)})#{VERSION_CONSTRAINT_PATTERN}(\s*)(#.*)?$/
      end

      PIP_PATTERN = lambda do |name|
        /^(\s{5,}-\s+)(#{Regexp.escape(name)})#{VERSION_CONSTRAINT_PATTERN}(\s*)(#.*)?$/
      end

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [ENVIRONMENT_REGEX]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = T.let([], T::Array[Dependabot::DependencyFile])

        environment_files.each do |file|
          updated_file = update_environment_file(file)
          # Always include a file (even if unchanged) to match expected behavior
          updated_files << (updated_file || file)
        end

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        filenames = dependency_files.map(&:name)
        raise "No environment.yml file found!" unless filenames.any? { |name| name.match?(/^environment\.ya?ml$/i) }
        # File found, all good
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def environment_files
        dependency_files.select { |f| f.name.match?(/^environment\.ya?ml$/i) }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::DependencyFile)) }
      def update_environment_file(file)
        content = file.content || ""
        updated_content = T.let(content.dup, String)

        return nil unless valid_yaml_content?(content, file.name)

        content_updated = update_dependencies_in_content(updated_content, file.name)
        return nil unless content_updated

        file.dup.tap { |f| f.content = updated_content }
      end

      sig { params(content: String, filename: String).returns(T::Boolean) }
      def valid_yaml_content?(content, filename)
        parsed_yaml = YAML.safe_load(content)
        return false unless parsed_yaml.is_a?(Hash) && parsed_yaml["dependencies"].is_a?(Array)

        true
      rescue Psych::SyntaxError, Psych::DisallowedClass => e
        raise Dependabot::DependencyFileNotParseable, "Invalid YAML in #{filename}: #{e.message}"
      end

      sig { params(content: String, filename: String).returns(T::Boolean) }
      def update_dependencies_in_content(content, filename)
        content_updated = false

        dependencies.each do |dependency|
          dependency_updated = update_dependency_in_content(content, dependency)
          if dependency_updated[:updated]
            content.replace(T.cast(dependency_updated[:content], String))
            content_updated = true
          elsif dependency_updated[:not_found]
            handle_dependency_not_found(dependency, filename)
          end
        end

        content_updated
      end

      sig { params(dependency: Dependabot::Dependency, filename: String).void }
      def handle_dependency_not_found(dependency, filename)
        return unless dependencies.length == 1

        raise Dependabot::DependencyFileNotFound,
              "Unable to find dependency #{dependency.name} in #{filename}"
      end

      sig do
        params(
          content: String,
          dependency: Dependabot::Dependency
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def update_dependency_in_content(content, dependency)
        return { updated: false, content: content, not_found: false } unless dependency.version

        # Try to update in main conda dependencies section
        conda_result = update_conda_dependency_in_content(content, dependency)
        return conda_result if conda_result[:updated] || conda_result[:not_found]

        # Try to update in pip dependencies section
        pip_result = update_pip_dependency_in_content(content, dependency)
        return pip_result if pip_result[:updated]

        # Dependency not found in either section
        { updated: false, content: content, not_found: true }
      end

      sig do
        params(
          content: String,
          dependency: Dependabot::Dependency
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def update_conda_dependency_in_content(content, dependency)
        # Pattern to match conda dependency lines (with optional channel prefix)
        # Matches: "  - numpy=1.26", "  - conda-forge::numpy>=1.21.0", "  - numpy >= 1.21.0  # comment", etc.
        # Enhanced to handle flexible indentation, space around operators, and comment preservation
        # But restrict to main dependencies section (not deeply nested like pip section)
        conda_patterns = [
          # With channel prefix - main dependencies section (2-4 spaces to avoid pip section)
          CONDA_CHANNEL_PATTERN.call(dependency.name),
          # Without channel prefix - main dependencies section (2-4 spaces to avoid pip section)
          CONDA_SIMPLE_PATTERN.call(dependency.name)
        ]

        conda_patterns.each do |pattern|
          next unless content.match?(pattern)

          updated_content = content.gsub(pattern) do
            prefix = ::Regexp.last_match(1)
            name = ::Regexp.last_match(2)
            whitespace_before_comment = ::Regexp.last_match(4) || ""
            comment = ::Regexp.last_match(5) || ""
            # Use the requirement from the dependency object, or default to =version
            new_requirement = get_requirement_for_dependency(dependency, "conda")
            "#{prefix}#{name}#{new_requirement}#{whitespace_before_comment}#{comment}"
          end
          return { updated: true, content: updated_content, not_found: false }
        end

        { updated: false, content: content, not_found: false }
      end

      sig do
        params(
          content: String,
          dependency: Dependabot::Dependency
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def update_pip_dependency_in_content(content, dependency)
        # Pattern to match pip dependency lines in pip section
        # Enhanced to handle flexible indentation for pip section (5+ spaces to distinguish from main deps),
        # better operator support, and multiple constraints like "requests>=2.25.0,<3.0"
        # Capture whitespace between requirement and comment to preserve formatting
        pip_pattern = PIP_PATTERN.call(dependency.name)

        if content.match?(pip_pattern)
          updated_content = content.gsub(pip_pattern) do
            prefix = ::Regexp.last_match(1)
            name = ::Regexp.last_match(2)
            whitespace_before_comment = ::Regexp.last_match(4) || ""
            comment = ::Regexp.last_match(5) || ""
            # Use the requirement from the dependency object, or default to ==version
            new_requirement = get_requirement_for_dependency(dependency, "pip")
            "#{prefix}#{name}#{new_requirement}#{whitespace_before_comment}#{comment}"
          end
          return { updated: true, content: updated_content, not_found: false }
        end

        { updated: false, content: content, not_found: false }
      end

      sig do
        params(
          dependency: Dependabot::Dependency,
          context: String
        ).returns(String)
      end
      def get_requirement_for_dependency(dependency, context)
        # Look for a requirement in the dependency's requirements array
        requirements = dependency.requirements
        requirement = nil

        requirement = requirements.first&.dig(:requirement) unless requirements.empty?

        return requirement if requirement && !requirement.empty?

        # Fallback to default format based on context
        if context == "pip"
          "==#{dependency.version}"
        else
          "=#{dependency.version}"
        end
      end
    end
  end
end

Dependabot::FileUpdaters.register("conda", Dependabot::Conda::FileUpdater)
