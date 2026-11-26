# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "psych"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

require "dependabot/azure_pipelines/constants"

module Dependabot
  module AzurePipelines
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/\.ya?ml$/]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        dependency_files.filter_map do |file|
          updated_content = updated_file_content(file)
          next if updated_content.nil? || updated_content == file.content

          updated_file(file: file, content: updated_content)
        end
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No dependency files!"
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def updated_file_content(file)
        content = file.content
        return nil if content.nil?

        dependencies.each do |dependency|
          content = replace_task_versions(content, dependency, file)
        end

        content
      end

      # Rewriting the reference in place rather than re-emitting the YAML keeps the
      # pipeline's comments, quoting and indentation intact.
      sig do
        params(
          content: String,
          dependency: Dependabot::Dependency,
          file: Dependabot::DependencyFile
        ).returns(String)
      end
      def replace_task_versions(content, dependency, file)
        # A file can pin the same task at more than one version, which the parser
        # keeps as separate requirements, so every pair has to be rewritten.
        requirement_pairs(dependency, file).each do |old_requirement, new_requirement|
          next if old_requirement == new_requirement

          updated = replace_task_reference(content, dependency.name, old_requirement, new_requirement)

          raise Dependabot::DependencyFileContentNotChanged, file.path if updated == content

          content = updated
        end

        content
      end

      # Use YAML node locations rather than searching source lines: text inside a
      # script block can look exactly like a task step but is not YAML structure.
      sig do
        params(content: String, name: String, old_requirement: String, new_requirement: String)
          .returns(String)
      end
      def replace_task_reference(content, name, old_requirement, new_requirement)
        document = T.cast(Psych.parse(content), T.nilable(Psych::Nodes::Document))
        root = T.cast(document&.root, T.nilable(Psych::Nodes::Node))
        return content unless root

        offsets = line_offsets(content)
        nodes = task_scalar_nodes(root, in_step_list: false)
        matches = nodes.filter_map do |node|
          reference = TASK_REFERENCE_PATTERN.match(T.cast(node.value, String))
          next unless reference && matching_task_reference?(reference, name, old_requirement)

          node_range_replacement(content, offsets, node, new_requirement)
        end

        matches.sort_by(&:first).reverse_each do |(range, replacement)|
          binary_content = content.dup.force_encoding(Encoding::BINARY)
          start_offset, end_offset = range
          binary_content[start_offset...end_offset] = replacement.b
          content = binary_content.force_encoding(content.encoding)
        end

        content
      end

      sig do
        params(reference: MatchData, name: String, version: String)
          .returns(T::Boolean)
      end
      def matching_task_reference?(reference, name, version)
        reference_name = reference[:name]
        reference_name&.casecmp(name)&.zero? == true && reference[:version] == version
      end

      sig { params(content: String).returns(T::Array[Integer]) }
      def line_offsets(content)
        offsets = [0]
        content.each_line { |line| offsets << (offsets.last + line.bytesize) }
        offsets
      end

      sig do
        params(
          content: String,
          offsets: T::Array[Integer],
          node: Psych::Nodes::Scalar,
          new_requirement: String
        ).returns(T.nilable([[Integer, Integer], String]))
      end
      def node_range_replacement(content, offsets, node, new_requirement)
        start_line = T.cast(node.start_line, Integer)
        end_line = T.cast(node.end_line, Integer)
        return nil unless start_line == end_line

        start_offset = T.must(offsets[start_line]) + T.cast(node.start_column, Integer)
        end_offset = T.must(offsets[end_line]) + T.cast(node.end_column, Integer)
        raw = content.byteslice(start_offset...end_offset)
        return nil unless raw

        first = raw[0]
        quote = first if first && ["'", '"'].include?(first) && raw.end_with?(first)
        value = quote ? T.must(raw.byteslice(1...-1)) : raw
        return nil unless value == T.cast(node.value, String)

        replacement_value = value.sub(/@[^@]+\z/, "@#{new_requirement}")
        replacement = quote ? "#{quote}#{replacement_value}#{quote}" : replacement_value
        [[start_offset, end_offset], replacement]
      end

      sig do
        params(node: Psych::Nodes::Node, in_step_list: T::Boolean)
          .returns(T::Array[Psych::Nodes::Scalar])
      end
      def task_scalar_nodes(node, in_step_list:)
        case node
        when Psych::Nodes::Sequence
          children = T.cast(node.children, T::Array[Psych::Nodes::Node])
          children.flat_map { |child| task_scalar_nodes(child, in_step_list: in_step_list) }
        when Psych::Nodes::Mapping
          task_nodes_for_mapping(node, in_step_list: in_step_list)
        else
          []
        end
      end

      sig do
        params(node: Psych::Nodes::Mapping, in_step_list: T::Boolean)
          .returns(T::Array[Psych::Nodes::Scalar])
      end
      def task_nodes_for_mapping(node, in_step_list:)
        children = T.cast(node.children, T::Array[Psych::Nodes::Node])
        pairs = children.each_slice(2).to_a
        step_list_parameter = step_list_parameter?(pairs)

        task_nodes_for_pairs(pairs, in_step_list: in_step_list) +
          child_task_nodes_for_pairs(pairs, step_list_parameter: step_list_parameter)
      end

      sig do
        params(
          pairs: T::Array[T::Array[Psych::Nodes::Node]],
          in_step_list: T::Boolean
        ).returns(T::Array[Psych::Nodes::Scalar])
      end
      def task_nodes_for_pairs(pairs, in_step_list:)
        return [] unless in_step_list

        pairs.filter_map do |pair|
          key = T.must(pair[0])
          value = T.must(pair[1])
          next unless scalar_key?(key, "task")

          value if value.is_a?(Psych::Nodes::Scalar)
        end
      end

      sig do
        params(
          pairs: T::Array[T::Array[Psych::Nodes::Node]],
          step_list_parameter: T::Boolean
        ).returns(T::Array[Psych::Nodes::Scalar])
      end
      def child_task_nodes_for_pairs(pairs, step_list_parameter:)
        pairs.flat_map do |pair|
          key = T.must(pair[0])
          value = T.must(pair[1])
          next [] unless key.is_a?(Psych::Nodes::Scalar)

          key_value = T.cast(key.value, String)
          child_is_step_list = key_value == "steps" || (step_list_parameter && key_value == "default")
          task_scalar_nodes(value, in_step_list: child_is_step_list)
        end
      end

      sig do
        params(pairs: T::Array[T::Array[Psych::Nodes::Node]])
          .returns(T::Boolean)
      end
      def step_list_parameter?(pairs)
        pairs.any? do |pair|
          key = T.must(pair[0])
          value = T.must(pair[1])
          scalar_key?(key, "type") &&
            value.is_a?(Psych::Nodes::Scalar) && T.cast(value.value, String) == "stepList"
        end
      end

      sig { params(node: Psych::Nodes::Node, value: String).returns(T::Boolean) }
      def scalar_key?(node, value)
        node.is_a?(Psych::Nodes::Scalar) && T.cast(node.value, String) == value
      end

      # Requirements and previous requirements are built in step with each other, so
      # they pair up by position.
      sig do
        params(dependency: Dependabot::Dependency, file: Dependabot::DependencyFile)
          .returns(T::Array[[String, String]])
      end
      def requirement_pairs(dependency, file)
        previous = dependency.previous_requirements || []

        dependency.requirements.each_with_index.filter_map do |requirement, index|
          next unless requirement.file == file.name

          old_requirement = previous[index]&.requirement
          new_requirement = requirement.requirement
          next unless old_requirement.is_a?(String) && new_requirement.is_a?(String)

          [old_requirement, new_requirement]
        end
      end
    end
  end
end

Dependabot::FileUpdaters.register("azure_pipelines", Dependabot::AzurePipelines::FileUpdater)
