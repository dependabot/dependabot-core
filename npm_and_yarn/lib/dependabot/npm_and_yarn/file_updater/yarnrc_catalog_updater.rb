# typed: strict
# frozen_string_literal: true

require "json"
require "yaml"
require "dependabot/npm_and_yarn/file_updater"
require "dependabot/npm_and_yarn/yarn_catalogs"

module Dependabot
  module NpmAndYarn
    class FileUpdater
      class YarnrcCatalogUpdater
        extend T::Sig

        class ScalarEdit < T::Struct
          const :binding, YarnCatalogs::Binding
          const :value, String
          const :replacement, String
          const :start_offset, Integer
          const :end_offset, Integer
        end

        sig { params(catalogs: YarnCatalogs, dependencies: T::Array[Dependency]).void }
        def initialize(catalogs:, dependencies:)
          @catalogs = catalogs
          @dependencies = dependencies
        end

        # Exact pins are temporary resolution inputs, never the returned PR configuration.
        sig { params(pins: T::Hash[String, String]).returns(String) }
        def updated_content(pins: {})
          content = T.must(T.must(@catalogs.config_file).content)
          expected = YarnCatalogs.parse_configuration(content)
          edits = scalar_edits(content, pins)
          edits.each do |edit|
            catalog_mapping(expected, edit.binding)[edit.binding.name] = edit.value
          end
          edits.sort_by(&:start_offset).reverse_each do |edit|
            content = T.must(content[0...edit.start_offset]) + edit.replacement + T.must(content[edit.end_offset..])
          end
          unless YarnCatalogs.parse_configuration(content) == expected
            raise DependencyFileNotResolvable, "Yarn catalog edit changed unplanned configuration values"
          end

          content
        end

        private

        sig do
          params(configuration: T::Hash[String, Object], binding: YarnCatalogs::Binding)
            .returns(T::Hash[String, Object])
        end
        def catalog_mapping(configuration, binding)
          name = binding.reference.delete_prefix("catalog:")
          return T.cast(configuration["catalog"], T::Hash[String, Object]) if name.empty?

          named_catalogs = T.cast(configuration["catalogs"], T::Hash[String, Object])
          T.cast(named_catalogs[name], T::Hash[String, Object])
        end

        sig { params(content: String, pins: T::Hash[String, String]).returns(T::Array[ScalarEdit]) }
        def scalar_edits(content, pins)
          # Psych versions disagree on whether the initial BOM contributes to
          # column marks. Parse without it and translate back to the source.
          yaml_content = content.delete_prefix("\uFEFF")
          root = YAML.parse_stream(yaml_content).children.first&.children&.first
          offsets = T.let([content.length - yaml_content.length], T::Array[Integer])
          # Match Psych's line breaks without changing the original terminators.
          yaml_content.scan(/\r\n|[\r\n\u0085\u2028\u2029]/) do
            offsets << (T.must(offsets.first) + T.must(Regexp.last_match).end(0))
          end

          @catalogs.bindings.filter_map do |binding|
            value = pins[binding.name] || updated_requirement(binding)&.requirement_string
            next if value.nil?

            @catalogs.validate_update!(binding.name)
            node = scalar_node(root, binding)
            next if value == binding.requirement

            scalar_edit(binding, value, node, offsets)
          end
        end

        sig do
          params(
            binding: YarnCatalogs::Binding,
            value: String,
            node: Psych::Nodes::Scalar,
            offsets: T::Array[Integer]
          ).returns(ScalarEdit)
        end
        def scalar_edit(binding, value, node, offsets)
          ScalarEdit.new(
            binding: binding,
            value: value,
            replacement: scalar_content(node, value),
            start_offset: T.must(offsets[node.start_line]) + node.start_column,
            end_offset: T.must(offsets[node.end_line]) + node.end_column
          )
        end

        sig { params(node: Psych::Nodes::Scalar, value: String).returns(String) }
        def scalar_content(node, value)
          case node.style
          when Psych::Nodes::Scalar::DOUBLE_QUOTED then value.to_json
          when Psych::Nodes::Scalar::SINGLE_QUOTED then "'#{value.gsub("'", "''")}'"
          else YAML.safe_load(value) == value ? value : value.to_json
          end
        end

        sig { params(binding: YarnCatalogs::Binding).returns(T.nilable(DependencyRequirement)) }
        def updated_requirement(binding)
          @dependencies.find { |dependency| dependency.name == binding.name }&.requirements&.find do |requirement|
            requirement.file == @catalogs.config_file&.name &&
              requirement.metadata_string("yarn_catalog_reference") == binding.reference &&
              requirement.metadata_string("yarn_catalog_package") == binding.name
          end
        end

        sig do
          params(root: T.nilable(Psych::Nodes::Node), binding: YarnCatalogs::Binding).returns(Psych::Nodes::Scalar)
        end
        def scalar_node(root, binding)
          name = binding.reference.delete_prefix("catalog:")
          path = name.empty? ? ["catalog", binding.name] : ["catalogs", name, binding.name]
          unsupported_scalar!(binding.name) unless root

          node = path.reduce(root) { |parent, key| mapping_value(parent, key, binding.name) }
          unless node.is_a?(Psych::Nodes::Scalar) && node.anchor.nil? &&
                 node.value == binding.requirement && node.start_line == node.end_line
            unsupported_scalar!(binding.name)
          end
          node
        end

        sig { params(node: Psych::Nodes::Node, key: String, name: String).returns(Psych::Nodes::Node) }
        def mapping_value(node, key, name)
          unsupported_scalar!(name) unless node.is_a?(Psych::Nodes::Mapping) && node.anchor.nil?

          children = T.cast(node.children, T::Array[Psych::Nodes::Node])
          matches = children.each_slice(2).select do |key_node, _value|
            key_node.is_a?(Psych::Nodes::Scalar) && key_node.value == key
          end
          unsupported_scalar!(name) unless matches.one?
          T.must(T.must(matches.first)[1])
        end

        sig { params(name: String).returns(T.noreturn) }
        def unsupported_scalar!(name)
          raise ToolFeatureNotSupported.new(
            tool_name: "yarn", tool_type: "package_manager", feature: "#{name}: ambiguous catalog scalar"
          )
        end
      end
    end
  end
end
