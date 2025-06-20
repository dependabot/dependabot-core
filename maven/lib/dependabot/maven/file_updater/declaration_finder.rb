# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "dependabot/maven/file_updater"
require "dependabot/maven/file_parser"
require "dependabot/maven/file_parser/property_value_finder"

module Dependabot
  module Maven
    class FileUpdater
      class DeclarationFinder
        extend T::Sig

        DECLARATION_REGEX = %r{
              <parent>.*?</parent>|
              <dependency>.*?</dependency>|
              <plugin>.*?(?:<plugin>.*?</plugin>.*)?</plugin>|
              <extension>.*?</extension>|
              <path>.*?</path>|
              <artifactItem>.*?</artifactItem>
            }mx

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :declaring_requirement

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            declaring_requirement: T::Hash[Symbol, T.untyped]
          ).void
        end
        def initialize(dependency:, dependency_files:, declaring_requirement:)
          @dependency = dependency
          @dependency_files = dependency_files
          @declaring_requirement = declaring_requirement
          @declaration_strings = T.let(nil, T.nilable(T::Array[String]))
          @property_value_finder = T.let(nil, T.nilable(Maven::FileParser::PropertyValueFinder))
        end

        sig { returns(T::Array[String]) }
        def declaration_strings
          @declaration_strings ||= fetch_pom_declaration_strings
        end

        sig { returns(T::Array[Nokogiri::XML::Document]) }
        def declaration_nodes
          declaration_strings.map do |declaration_string|
            Nokogiri::XML(declaration_string)
          end
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        def declaring_pom
          filename = declaring_requirement.fetch(:file) || declaring_requirement.dig(:metadata, :pom_file)
          declaring_pom = dependency_files.find { |f| f.name == filename }
          return declaring_pom if declaring_pom

          raise "No pom found with name #{filename}!"
        end

        sig { returns(String) }
        def dependency_name
          dependency.name
        end

        sig { returns(T::Array[String]) }
        def fetch_pom_declaration_strings
          deep_find_declarations(T.must(declaring_pom.content)).select do |nd|
            node = Nokogiri::XML(nd)
            node.remove_namespaces!
            next false unless node_group_id(node)
            next false unless node.at_xpath("./*/artifactId")

            node_name = [
              node_group_id(node),
              evaluated_value(node.at_xpath("./*/artifactId").content.strip)
            ].compact.join(":")

            if node.at_xpath("./*/classifier")
              classifier = evaluated_value(node.at_xpath("./*/classifier").content.strip)
              dep_classifier = dependency.requirements.first&.dig(:metadata, :classifier)
              next false if classifier != dep_classifier
            end

            next false unless node_name == dependency_name
            next false unless packaging_type_matches?(node)
            next false unless scope_matches?(node)

            declaring_requirement_matches?(node)
          end
        end

        sig { params(node: Nokogiri::XML::Document).returns(T.nilable(String)) }
        def node_group_id(node)
          return unless node.at_xpath("./*/groupId") || node.at_xpath("./plugin")
          return "org.apache.maven.plugins" unless node.at_xpath("./*/groupId")

          evaluated_value(node.at_xpath("./*/groupId").content.strip)
        end

        sig { params(string: String).returns(T::Array[String]) }
        def deep_find_declarations(string)
          string.scan(DECLARATION_REGEX).flat_map do |matching_node|
            [matching_node, *deep_find_declarations(matching_node[1..-1].to_s)]
          end.flatten
        end

        sig { params(node: Nokogiri::XML::Document).returns(T::Boolean) }
        def declaring_requirement_matches?(node)
          node_requirement = node.at_css("version")&.content&.strip

          if declaring_requirement.dig(:metadata, :property_name)
            return false unless node_requirement

            property_name =
              node_requirement
              .match(Maven::FileParser::PROPERTY_REGEX)
              &.named_captures
              &.fetch("property")

            property_name == declaring_requirement[:metadata][:property_name]
          else
            node_requirement == declaring_requirement.fetch(:requirement)
          end
        end

        sig { params(node: Nokogiri::XML::Document).returns(T::Boolean) }
        def packaging_type_matches?(node)
          type = declaring_requirement.dig(:metadata, :packaging_type)
          type == packaging_type(node)
        end

        sig { params(node: Nokogiri::XML::Document).returns(T::Boolean) }
        def scope_matches?(node)
          dependency_type = declaring_requirement.fetch(:groups)
          node_type = dependency_scope(node) == "test" ? ["test"] : []

          dependency_type == node_type
        end

        sig { params(dependency_node: Nokogiri::XML::Document).returns(String) }
        def packaging_type(dependency_node)
          return "pom" if dependency_node.child.node_name == "parent"
          return "jar" unless dependency_node.at_xpath("./*/type")

          packaging_type_content = dependency_node.at_xpath("./*/type")
                                                  .content.strip

          evaluated_value(packaging_type_content)
        end

        sig { params(dependency_node: Nokogiri::XML::Document).returns(String) }
        def dependency_scope(dependency_node)
          return "compile" unless dependency_node.at_xpath("./*/scope")

          scope_content = dependency_node.at_xpath("./*/scope").content.strip
          scope_content = evaluated_value(scope_content)

          scope_content.empty? ? "compile" : scope_content
        end

        sig { params(value: String).returns(String) }
        def evaluated_value(value)
          return value unless value.match?(Maven::FileParser::PROPERTY_REGEX)

          match_data = value.match(Maven::FileParser::PROPERTY_REGEX)
          return value unless match_data

          property_name = match_data.named_captures.fetch("property")
          return value unless property_name

          property_value =
            property_value_finder
            .property_details(
              property_name: property_name,
              callsite_pom: declaring_pom
            )&.fetch(:value)

          return value unless property_value

          value.gsub(
            match_data.to_s,
            property_value
          )
        end

        sig { returns(Maven::FileParser::PropertyValueFinder) }
        def property_value_finder
          @property_value_finder ||=
            Maven::FileParser::PropertyValueFinder
            .new(dependency_files: dependency_files)
        end
      end
    end
  end
end
