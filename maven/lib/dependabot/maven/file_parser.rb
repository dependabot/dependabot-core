# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/maven/version"
require "dependabot/errors"

# The best Maven documentation is at:
# - http://maven.apache.org/pom.html
module Dependabot
  module Maven
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig
      require "dependabot/file_parsers/base/dependency_set"
      require_relative "file_parser/property_value_finder"

      # The following "dependencies" are candidates for updating:
      # - The project's parent
      # - Any dependencies (incl. those in dependencyManagement or plugins)
      # - Any plugins (incl. those in pluginManagement)
      # - Any extensions
      DEPENDENCY_SELECTOR = "project > parent, " \
                            "dependencies > dependency, " \
                            "extensions > extension, " \
                            "annotationProcessorPaths > path"
      PLUGIN_SELECTOR     = "plugins > plugin"
      EXTENSION_SELECTOR  = "extensions > extension"
      PLUGIN_ARTIFACT_ITEMS_SELECTOR = "plugins > plugin > executions > execution > " \
                                       "configuration > artifactItems > artifactItem"

      # Regex to get the property name from a declaration that uses a property
      PROPERTY_REGEX = /\$\{(?<property>.*?)\}/

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new
        pomfiles.each { |pom| dependency_set += pomfile_dependencies(pom) }
        extensionfiles.each { |extension| dependency_set += extensionfile_dependencies(extension) }
        dependency_set.dependencies
      end

      private

      sig { params(pom: Dependabot::DependencyFile).returns(DependencySet) }
      def pomfile_dependencies(pom)
        dependency_set = DependencySet.new

        errors = T.let([], T::Array[Dependabot::DependencyFileNotEvaluatable])
        doc = Nokogiri::XML(pom.content)
        doc.remove_namespaces!

        doc.css(DEPENDENCY_SELECTOR).each do |dependency_node|
          dep = dependency_from_dependency_node(pom, dependency_node)
          dependency_set << dep if dep
        rescue DependencyFileNotEvaluatable => e
          errors << e
        end

        doc.css(PLUGIN_SELECTOR, PLUGIN_ARTIFACT_ITEMS_SELECTOR).each do |dependency_node|
          dep = dependency_from_plugin_node(pom, dependency_node)
          dependency_set << dep if dep
        rescue DependencyFileNotEvaluatable => e
          errors << e
        end

        raise T.must(errors.first) if errors.any? && dependency_set.dependencies.none?

        dependency_set
      end

      sig { params(extension: Dependabot::DependencyFile).returns(DependencySet) }
      def extensionfile_dependencies(extension)
        dependency_set = DependencySet.new

        errors = T.let([], T::Array[Dependabot::DependencyFileNotEvaluatable])
        doc = Nokogiri::XML(extension.content)
        doc.remove_namespaces!

        doc.css(EXTENSION_SELECTOR).each do |dependency_node|
          dep = dependency_from_dependency_node(extension, dependency_node)
          dependency_set << dep if dep
        rescue DependencyFileNotEvaluatable => e
          errors << e
        end

        raise T.must(errors.first) if errors.any? && dependency_set.dependencies.none?

        dependency_set
      end

      sig do
        params(pom: Dependabot::DependencyFile,
               dependency_node: Nokogiri::XML::Element).returns(T.nilable(Dependabot::Dependency))
      end
      def dependency_from_dependency_node(pom, dependency_node)
        return unless (name = dependency_name(dependency_node, pom))
        return if internal_dependency_names.include?(name)

        build_dependency(pom, dependency_node, name)
      end

      sig do
        params(pom: Dependabot::DependencyFile,
               dependency_node: Nokogiri::XML::Element).returns(T.nilable(Dependabot::Dependency))
      end
      def dependency_from_plugin_node(pom, dependency_node)
        return unless (name = plugin_name(dependency_node, pom))
        return if internal_dependency_names.include?(name)

        build_dependency(pom, dependency_node, name)
      end

      sig do
        params(pom: Dependabot::DependencyFile, dependency_node: Nokogiri::XML::Element,
               name: String).returns(T.nilable(Dependabot::Dependency))
      end
      def build_dependency(pom, dependency_node, name)
        property_details =
          {
            property_name: version_property_name(dependency_node),
            property_source: property_source(dependency_node, pom)
          }.compact

        Dependency.new(
          name: name,
          version: dependency_version(pom, dependency_node),
          package_manager: "maven",
          requirements: [{
            requirement: dependency_requirement(pom, dependency_node),
            file: pom.name,
            groups: dependency_groups(pom, dependency_node),
            source: nil,
            metadata: {
              packaging_type: packaging_type(pom, dependency_node),
              classifier: dependency_classifier(dependency_node, pom)
            }.merge(property_details).compact
          }]
        )
      end

      sig do
        params(dependency_node: Nokogiri::XML::Element,
               pom: Dependabot::DependencyFile).returns(T.nilable(String))
      end
      def dependency_name(dependency_node, pom)
        return unless dependency_node.at_xpath("./groupId")
        return unless dependency_node.at_xpath("./artifactId")

        [
          evaluated_value(
            dependency_node.at_xpath("./groupId").content.strip,
            pom
          ),
          evaluated_value(
            dependency_node.at_xpath("./artifactId").content.strip,
            pom
          )
        ].join(":")
      end

      sig do
        params(dependency_node: Nokogiri::XML::Element, pom: Dependabot::DependencyFile).returns(T.nilable(String))
      end
      def dependency_classifier(dependency_node, pom)
        return unless dependency_node.at_xpath("./classifier")

        evaluated_value(
          dependency_node.at_xpath("./classifier").content.strip,
          pom
        )
      end

      sig do
        params(dependency_node: Nokogiri::XML::Element, pom: Dependabot::DependencyFile).returns(T.nilable(String))
      end
      def plugin_name(dependency_node, pom)
        return unless plugin_group_id(pom, dependency_node)
        return unless dependency_node.at_xpath("./artifactId")

        [
          plugin_group_id(pom, dependency_node),
          evaluated_value(
            dependency_node.at_xpath("./artifactId").content.strip,
            pom
          )
        ].join(":")
      end

      sig { params(pom: Dependabot::DependencyFile, node: Nokogiri::XML::Element).returns(T.nilable(String)) }
      def plugin_group_id(pom, node)
        return "org.apache.maven.plugins" unless node.at_xpath("./groupId")

        evaluated_value(
          node.at_xpath("./groupId").content.strip,
          pom
        )
      end

      sig do
        params(pom: Dependabot::DependencyFile, dependency_node: Nokogiri::XML::Element).returns(T.nilable(String))
      end
      def dependency_version(pom, dependency_node)
        requirement = dependency_requirement(pom, dependency_node)
        return nil unless requirement

        # If a range is specified then we can't tell the exact version
        return nil if requirement.include?(",")

        # Remove brackets if present (and not denoting a range)
        requirement.gsub(/[\(\)\[\]]/, "").strip
      end

      sig do
        params(pom: Dependabot::DependencyFile, dependency_node: Nokogiri::XML::Element).returns(T.nilable(String))
      end
      def dependency_requirement(pom, dependency_node)
        return unless dependency_node.at_xpath("./version")

        version_content = dependency_node.at_xpath("./version").content.strip
        version_content = evaluated_value(version_content, pom)

        version_content.empty? ? nil : version_content
      end

      sig { params(pom: Dependabot::DependencyFile, dependency_node: Nokogiri::XML::Element).returns(T::Array[String]) }
      def dependency_groups(pom, dependency_node)
        dependency_scope(pom, dependency_node) == "test" ? ["test"] : []
      end

      sig { params(pom: Dependabot::DependencyFile, dependency_node: Nokogiri::XML::Element).returns(String) }
      def dependency_scope(pom, dependency_node)
        return "compile" unless dependency_node.at_xpath("./scope")

        scope_content = dependency_node.at_xpath("./scope").content.strip
        scope_content = evaluated_value(scope_content, pom)

        scope_content.empty? ? "compile" : scope_content
      end

      sig { params(pom: Dependabot::DependencyFile, dependency_node: Nokogiri::XML::Element).returns(String) }
      def packaging_type(pom, dependency_node)
        return "pom" if dependency_node.node_name == "parent"
        return "jar" unless dependency_node.at_xpath("./type")

        packaging_type_content = dependency_node.at_xpath("./type")
                                                .content.strip

        evaluated_value(packaging_type_content, pom)
      end

      sig { params(dependency_node: Nokogiri::XML::Element).returns(T.nilable(String)) }
      def version_property_name(dependency_node)
        return unless dependency_node.at_xpath("./version")

        version_content = dependency_node.at_xpath("./version").content.strip
        return unless version_content.match?(PROPERTY_REGEX)

        version_content
          .match(PROPERTY_REGEX)
          .named_captures.fetch("property")
      end

      sig { params(value: String, pom: Dependabot::DependencyFile).returns(String) }
      def evaluated_value(value, pom)
        return value unless value.match?(PROPERTY_REGEX)

        property_name = T.must(value.match(PROPERTY_REGEX))
                         .named_captures.fetch("property")
        property_value = value_for_property(T.must(property_name), pom)

        new_value = value.gsub(value.match(PROPERTY_REGEX).to_s, property_value)
        evaluated_value(new_value, pom)
      end

      sig do
        params(dependency_node: Nokogiri::XML::Element, pom: Dependabot::DependencyFile).returns(T.nilable(String))
      end
      def property_source(dependency_node, pom)
        property_name = version_property_name(dependency_node)
        return unless property_name

        declaring_pom =
          property_value_finder
          .property_details(property_name: property_name, callsite_pom: pom)
          &.fetch(:file)

        return declaring_pom if declaring_pom

        msg = "Property not found: #{property_name}"
        raise DependencyFileNotEvaluatable, msg
      end

      sig { params(property_name: String, pom: Dependabot::DependencyFile).returns(String) }
      def value_for_property(property_name, pom)
        value =
          property_value_finder
          .property_details(property_name: property_name, callsite_pom: pom)
          &.fetch(:value)

        return value if value

        msg = "Property not found: #{property_name}"
        raise DependencyFileNotEvaluatable, msg
      end

      # Cached, since this can makes calls to the registry (to get property
      # values from parent POMs)
      sig { returns(Dependabot::Maven::FileParser::PropertyValueFinder) }
      def property_value_finder
        @property_value_finder ||= T.let(
          PropertyValueFinder.new(dependency_files: dependency_files, credentials: credentials.map(&:to_s)),
          T.nilable(Dependabot::Maven::FileParser::PropertyValueFinder)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pomfiles
        @pomfiles ||= T.let(
          dependency_files.select do |f|
            f.name.end_with?(".xml") && !f.name.end_with?("extensions.xml")
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def extensionfiles
        @extensionfiles ||= T.let(
          dependency_files.select { |f| f.name.end_with?("extensions.xml") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[String]) }
      def internal_dependency_names
        @internal_dependency_names ||= T.let(
          dependency_files.filter_map do |pom|
            doc = Nokogiri::XML(pom.content)
            group_id = doc.at_css("project > groupId") ||
                       doc.at_css("project > parent > groupId")
            artifact_id = doc.at_css("project > artifactId")

            next unless group_id && artifact_id

            [group_id.content.strip, artifact_id.content.strip].join(":")
          end,
          T.nilable(T::Array[String])
        )
      end

      sig { override.void }
      def check_required_files
        raise "No pom.xml!" unless get_original_file("pom.xml")
      end
    end
  end
end

Dependabot::FileParsers.register("maven", Dependabot::Maven::FileParser)
