# typed: strict
# frozen_string_literal: true

require "nokogiri"
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
        # binding.irb
        files = original_files.dup

        # The UpdateChecker ensures the order of requirements is preserved
        # when updating, so we can zip them together in new/old pairs.
        reqs = dependency.requirements.zip(dependency.previous_requirements.to_a)
                         .reject { |new_req, old_req| new_req == old_req }

        # Loop through each changed requirement and update the files
        reqs.each do |new_req, old_req|
          raise "Bad req match" unless new_req[:file] == T.must(old_req)[:file]
          next if new_req[:requirement] == T.must(old_req)[:requirement]

          if new_req.dig(:metadata, :property_name)
            files = update_pomfiles_for_property_change(files, new_req)
            pom = files.find { |f| f.name == new_req.fetch(:file) }
            files[T.must(files.index(pom))] =
              remove_property_suffix_in_pom(dependency, T.must(pom), T.must(old_req))
          else
            file = files.find { |f| f.name == new_req.fetch(:file) }
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
          original_file_declarations.each do |old_dec|
            updated_content = updated_content.gsub(old_dec) do
              updated_file_declaration(old_dec, previous_req, requirement)
            end
          end
        else
          updated_content = add_new_declaration(updated_content, dependency, requirement)
        end

        binding.irb

        raise "Expected content to change!" if updated_content == file.content

        updated_file(file: file, content: updated_content)
      end

      sig do
        params(
          content: String,
          dependency: Dependabot::Dependency,
          requirement: T::Hash[Symbol, T.untyped]
        ).returns(String)
      end
      def add_new_declaration(content, dependency, requirement) # rubocop:disable Metrics/AbcSize
        binding.irb
        doc = Nokogiri::XML(content) { |config| config.default_xml.noblanks }
        doc.remove_namespaces!

        project = doc.at_xpath("//project")
        raise "<project> element not found in the XML content" unless project

        dependency_management = project.at_xpath("dependencyManagement")
        unless dependency_management
          dependency_management = Nokogiri::XML::Node.new("dependencyManagement", doc)
          dependencies = Nokogiri::XML::Node.new("dependencies", doc)
          dependency_management.add_child(dependencies)
          project.add_child(dependency_management)
        end

        dependencies = dependency_management.at_xpath("dependencies")
        unless dependencies
          dependencies = Nokogiri::XML::Node.new("dependencies", doc)
          dependency_management.add_child(dependencies)
        end

        dependency_node = Nokogiri::XML::Node.new("dependency", doc)

        group_id = Nokogiri::XML::Node.new("groupId", doc)
        group_id.content = dependency.name.split(":").first
        dependency_node.add_child(group_id)

        artifact_id = Nokogiri::XML::Node.new("artifactId", doc)
        artifact_id.content = dependency.name.split(":").last
        dependency_node.add_child(artifact_id)

        version = Nokogiri::XML::Node.new("version", doc)
        version.content = requirement.fetch(:requirement)
        dependency_node.add_child(version)

        dependencies.add_child(dependency_node)

        doc.to_xml
      end

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
    end
  end
end

Dependabot::FileUpdaters.register("maven", Dependabot::Maven::FileUpdater)
