# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "rexml/document"
require "sorbet-runtime"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Maven
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/declaration_finder"
      require_relative "file_updater/property_value_updater"

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /^pom\.xml$/, %r{/pom\.xml$},
          /.*\.xml$/, %r{/.*\.xml$},
          /^extensions.\.xml$/, %r{/extensions\.xml$}
        ]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = T.let(dependency_files.dup, T::Array[Dependabot::DependencyFile])

        # Loop through each of the changed requirements, applying changes to
        # all pom and extensions files for that change. Note that the logic
        # is different here to other package managers because Maven has property
        # inheritance across files
        dependencies.each do |dependency|
          updated_files = update_files_for_dependency(
            original_files: updated_files,
            dependency: dependency
          )
        end

        updated_files.select! { |f| f.name.end_with?(".xml") }
        updated_files.reject! { |f| dependency_files.include?(f) }

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        raise "No pom.xml!" unless get_original_file("pom.xml")
      end

      # rubocop:disable Metrics/AbcSize
      sig do
        params(
          original_files: T::Array[Dependabot::DependencyFile],
          dependency: Dependabot::Dependency
        )
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def update_files_for_dependency(original_files:, dependency:)
        files = original_files.dup

        # The UpdateChecker ensures the order of requirements is preserved
        # when updating, so we can zip them together in new/old pairs.
        reqs = dependency.requirements.zip(dependency.previous_requirements.to_a)
                         .reject { |new_req, old_req| new_req == old_req }

        # Loop through each changed requirement and update the files
        reqs.each do |new_req, old_req|
          raise "Bad req match" unless new_req[:file] == T.must(old_req)[:file]
          next if new_req[:requirement] == T.must(old_req)[:requirement]

          file_name = T.let(new_req.fetch(:file) || new_req.dig(:metadata, :pom_file), String)
          if new_req.dig(:metadata, :property_name)
            files = update_pomfiles_for_property_change(files, new_req)
            pom = files.find { |f| f.name == file_name }
            files[T.must(files.index(pom))] =
              remove_property_suffix_in_pom(dependency, T.must(pom), T.must(old_req))
          else
            file = files.find { |f| f.name == file_name }
            files[T.must(files.index(file))] =
              update_version_in_file(dependency, T.must(file), T.must(old_req), new_req)
          end
        end

        files
      end
      # rubocop:enable Metrics/AbcSize

      sig do
        params(
          pomfiles: T::Array[Dependabot::DependencyFile],
          req: T::Hash[Symbol, T.untyped]
        )
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def update_pomfiles_for_property_change(pomfiles, req)
        property_name = req.fetch(:metadata).fetch(:property_name)

        PropertyValueUpdater.new(dependency_files: pomfiles)
                            .update_pomfiles_for_property_change(
                              property_name: property_name,
                              callsite_pom: T.must(pomfiles.find { |f| f.name == req.fetch(:file) }),
                              updated_value: req.fetch(:requirement)
                            )
      end

      sig do
        params(
          dependency: Dependabot::Dependency,
          file: Dependabot::DependencyFile,
          previous_req: T::Hash[Symbol, T.untyped],
          requirement: T::Hash[Symbol, T.untyped]
        )
          .returns(Dependabot::DependencyFile)
      end
      def update_version_in_file(dependency, file, previous_req, requirement)
        updated_content = T.must(file.content)
        original_file_declarations = original_file_declarations(dependency, previous_req)

        if original_file_declarations.any?
          # If the file already has a declaration for this dependency, we
          # update the existing declaration with the new version.
          original_file_declarations.each do |old_dec|
            updated_content = updated_content.gsub(old_dec) do
              updated_file_declaration(old_dec, previous_req, requirement)
            end
          end
        else
          # If the file does not have a declaration for this dependency, we
          # add a new declaration for it.
          updated_content = add_new_declaration(updated_content, dependency, requirement)
        end

        raise "Expected content to change!" if updated_content == file.content

        updated_file(file: file, content: updated_content)
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/MethodLength
      sig do
        params(
          content: String,
          dependency: Dependabot::Dependency,
          requirement: T::Hash[Symbol, T.untyped]
        ).returns(String)
      end
      def add_new_declaration(content, dependency, requirement)
        doc = REXML::Document.new(content)

        project = doc.get_elements("//project").first
        raise "<project> element not found in the XML content" unless project

        # Detect indentation of the file from indentation of the project tag children
        base_indentation = project.children.find { |child| child.to_s.start_with?("\n") }&.to_s || "\n  "
        is_tabs = !base_indentation.to_s.scan(/\t+$/).length.zero? # rubocop:disable Style/ZeroLengthPredicate

        indent_size = get_indent_size(base_indentation, is_tabs)
        indent_level = get_indent_level(indent_size, is_tabs)

        dependency_management_indentation = base_indentation + indent_level
        dependencies_indentation = dependency_management_indentation + indent_level
        dependency_indentation = dependencies_indentation + indent_level

        dependency_management = project.get_elements("dependencyManagement").first
        dependency_management_created = false
        unless dependency_management
          # If there's no dependencyManagement element, create one
          project.add_text(base_indentation)
          dependency_management = REXML::Element.new("dependencyManagement", project)
          dependency_management_created = true
        end

        dependencies = dependency_management.get_elements("dependencies").first
        dependencies_created = false
        unless dependencies
          # If there's no dependencies element, create one
          dependency_management.add_text(dependency_management_indentation)
          dependencies = REXML::Element.new("dependencies", dependency_management)
          dependencies_created = true
        end

        # Narrow down the indentation of the dependency node by looking at other children in the dependencies element
        # in case indentation is not consistent with parent elements or if no items are present use default indentation
        dependencies_indentation = dependencies.children.find do |child|
          child.to_s.start_with?("\n")
        end&.to_s || dependencies_indentation

        if dependencies.children.last&.to_s&.start_with?("\n")
          dependencies.children.last.value = dependencies_indentation
        else
          dependencies.add_text(dependencies_indentation)
        end

        # Create the dependency element with the required fields, adding the appropriate indentation as text nodes
        add_dependency_entry(dependency, requirement, dependencies, dependency_indentation, dependencies_indentation)
        dependencies.add_text(dependency_management_indentation)

        dependency_management.add_text(base_indentation) if dependencies_created
        project.add_text("\n") if dependency_management_created

        doc.to_s
      end

      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/MethodLength

      sig do
        params(
          dep: Dependabot::Dependency,
          pom: Dependabot::DependencyFile,
          req: T::Hash[Symbol, T.untyped]
        )
          .returns(Dependabot::DependencyFile)
      end
      def remove_property_suffix_in_pom(dep, pom, req)
        updated_content = T.must(pom.content)

        original_file_declarations(dep, req).each do |old_declaration|
          updated_content = updated_content.gsub(old_declaration) do |old_dec|
            version_string =
              old_dec.match(%r{(?<=\<version\>).*(?=\</version\>)})
            cleaned_version_string = version_string.to_s.gsub(/(?<=\}).*/, "")

            old_dec.gsub(
              "<version>#{version_string}</version>",
              "<version>#{cleaned_version_string}</version>"
            )
          end
        end

        updated_file(file: pom, content: updated_content)
      end

      sig do
        params(
          dependency: Dependabot::Dependency,
          requirement: T::Hash[Symbol, T.untyped]
        )
          .returns(T::Array[String])
      end
      def original_file_declarations(dependency, requirement)
        declaration_finder(dependency, requirement).declaration_strings
      end

      sig do
        params(
          dependency: Dependabot::Dependency,
          requirement: T::Hash[Symbol, T.untyped]
        )
          .returns(DeclarationFinder)
      end
      def declaration_finder(dependency, requirement)
        @declaration_finders ||= T.let({}, T.nilable(T::Hash[Integer, DeclarationFinder]))
        @declaration_finders[dependency.hash + requirement.hash] =
          DeclarationFinder.new(
            dependency: dependency,
            declaring_requirement: requirement,
            dependency_files: dependency_files
          )
      end

      sig do
        params(
          old_declaration: String,
          previous_req: T::Hash[Symbol, T.untyped],
          requirement: T::Hash[Symbol, T.untyped]
        )
          .returns(String)
      end
      def updated_file_declaration(old_declaration, previous_req, requirement)
        original_req_string = previous_req.fetch(:requirement)

        old_declaration.gsub(
          /(?<=\s|>)#{Regexp.quote(original_req_string)}(?=\s|<)/,
          requirement.fetch(:requirement)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def original_pomfiles
        @original_pomfiles ||= T.let(
          dependency_files.select { |f| f.name.end_with?("pom.xml") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig do
        params(dependency: Dependabot::Dependency, requirement: T::Hash[Symbol, T.untyped],
               dependencies_node: REXML::Element, current_indentation_level: String,
               parent_indentation_level: String).void
      end
      def add_dependency_entry(dependency, requirement, dependencies_node, current_indentation_level,
                               parent_indentation_level)
        dependency_node = REXML::Element.new("dependency", dependencies_node)
        dependency_node.add_text(current_indentation_level)
        group_id = REXML::Element.new("groupId", dependency_node)
        group_id.text = dependency.name.split(":").first
        dependency_node.add_text(current_indentation_level)
        artifact_id = REXML::Element.new("artifactId", dependency_node)
        artifact_id.text = dependency.name.split(":").last
        dependency_node.add_text(current_indentation_level)
        version = REXML::Element.new("version", dependency_node)
        version.text = requirement.fetch(:requirement)
        dependency_node.add_text(parent_indentation_level)
      end

      sig { params(base_indentation: String, is_tabs: T::Boolean).returns(Integer) }
      def get_indent_size(base_indentation, is_tabs)
        if is_tabs
          indent_size = base_indentation.to_s.scan(/\t+$/).length
          indent_size.positive? ? indent_size : 1
        else
          base_indentation.to_s.scan(/ +$/).last&.length || 2
        end
      end

      sig { params(indent_size: Integer, is_tabs: T::Boolean).returns(String) }
      def get_indent_level(indent_size, is_tabs)
        if is_tabs
          "\t" * indent_size
        else
          " " * indent_size
        end
      end
    end
  end
end

Dependabot::FileUpdaters.register("maven", Dependabot::Maven::FileUpdater)
