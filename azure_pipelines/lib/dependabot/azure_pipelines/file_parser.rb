# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

require "dependabot/azure_pipelines/constants"
require "dependabot/azure_pipelines/package_manager"
# DependencySet compares versions when it merges two occurrences of the same task,
# which needs the version class registered.
require "dependabot/azure_pipelines/version"

module Dependabot
  module AzurePipelines
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dependency_files.each do |file|
          parse_file(file).each { |dependency| dependency_set << dependency }
        end

        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(name: ECOSYSTEM, package_manager: PackageManager.new),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No dependency files!"
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_file(file)
        content = file.content
        return [] if content.nil? || content.strip.empty?

        parsed = begin
          YAML.safe_load(content, aliases: true, permitted_classes: [Date, Time])
        rescue Psych::Exception => e
          raise Dependabot::DependencyFileNotParseable.new(file.path, e.message)
        end

        task_references(parsed).filter_map { |reference| build_dependency(reference, file) }
      end

      # Task references occur in step lists, including deployment hooks and
      # stepList parameter defaults. Requiring a mapping to be an entry in one of
      # those lists avoids treating arbitrary arrays of objects as task steps.
      sig { params(node: T.anything, in_step_list: T::Boolean).returns(T::Array[String]) }
      def task_references(node, in_step_list: false)
        case node
        when Hash
          task = node["task"]
          references = in_step_list && task.is_a?(String) ? [task] : []
          step_list_parameter = node["type"] == "stepList"
          references + node.each_with_object([]) do |(key, value), nested|
            child_is_step_list = key == "steps" || (step_list_parameter && key == "default")
            nested.concat(task_references(value, in_step_list: child_is_step_list))
          end
        when Array
          node.flat_map { |value| task_references(value, in_step_list: in_step_list) }
        else
          []
        end
      end

      sig do
        params(reference: String, file: Dependabot::DependencyFile)
          .returns(T.nilable(Dependabot::Dependency))
      end
      def build_dependency(reference, file)
        match = TASK_REFERENCE_PATTERN.match(reference.strip)
        return nil unless match

        name = T.must(match[:name])
        version = T.must(match[:version])

        # A name or version built from a template expression only resolves at runtime.
        return nil if name.match?(TEMPLATE_EXPRESSION_PATTERN)
        return nil unless version.match?(TASK_VERSION_PATTERN)

        Dependabot::Dependency.new(
          name: name,
          version: version,
          package_manager: PACKAGE_MANAGER,
          requirements: [{
            requirement: version,
            file: file.name,
            source: nil,
            groups: []
          }]
        )
      end
    end
  end
end

Dependabot::FileParsers.register("azure_pipelines", Dependabot::AzurePipelines::FileParser)
