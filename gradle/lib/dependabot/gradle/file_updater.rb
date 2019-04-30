# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/gradle/file_parser"

module Dependabot
  module Gradle
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/dependency_set_updater"
      require_relative "file_updater/property_value_updater"

      def self.updated_files_regex
        [/^build\.gradle$/, %r{/build\.gradle$}]
      end

      def updated_dependency_files
        updated_files = buildfiles.dup

        # Loop through each of the changed requirements, applying changes to
        # all buildfiles for that change. Note that the logic is different
        # here to other languages because Java has property inheritance across
        # files (although we're not supporting it for gradle yet).
        dependencies.each do |dependency|
          updated_files = update_buildfiles_for_dependency(
            buildfiles: updated_files,
            dependency: dependency
          )
        end

        updated_files = updated_files.reject { |f| buildfiles.include?(f) }

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def check_required_files
        raise "No build.gradle!" unless get_original_file("build.gradle")
      end

      def update_buildfiles_for_dependency(buildfiles:, dependency:)
        files = buildfiles.dup

        # The UpdateChecker ensures the order of requirements is preserved
        # when updating, so we can zip them together in new/old pairs.
        reqs = dependency.requirements.zip(dependency.previous_requirements).
               reject { |new_req, old_req| new_req == old_req }

        # Loop through each changed requirement and update the buildfiles
        reqs.each do |new_req, old_req|
          raise "Bad req match" unless new_req[:file] == old_req[:file]
          next if new_req[:requirement] == old_req[:requirement]

          buildfile = files.find { |f| f.name == new_req.fetch(:file) }

          if new_req.dig(:metadata, :property_name)
            files = update_files_for_property_change(files, old_req, new_req)
          elsif new_req.dig(:metadata, :dependency_set)
            files = update_files_for_dep_set_change(files, old_req, new_req)
          else
            files[files.index(buildfile)] =
              update_version_in_buildfile(
                dependency,
                buildfile,
                old_req,
                new_req
              )
          end
        end

        files
      end

      def update_files_for_property_change(buildfiles, old_req, new_req)
        files = buildfiles.dup
        property_name = new_req.fetch(:metadata).fetch(:property_name)
        buildfile = files.find { |f| f.name == new_req.fetch(:file) }

        PropertyValueUpdater.new(dependency_files: files).
          update_files_for_property_change(
            property_name: property_name,
            callsite_buildfile: buildfile,
            previous_value: old_req.fetch(:requirement),
            updated_value: new_req.fetch(:requirement)
          )
      end

      def update_files_for_dep_set_change(buildfiles, old_req, new_req)
        files = buildfiles.dup
        dependency_set = new_req.fetch(:metadata).fetch(:dependency_set)
        buildfile = files.find { |f| f.name == new_req.fetch(:file) }

        DependencySetUpdater.new(dependency_files: files).
          update_files_for_dep_set_change(
            dependency_set: dependency_set,
            buildfile: buildfile,
            previous_requirement: old_req.fetch(:requirement),
            updated_requirement: new_req.fetch(:requirement)
          )
      end

      def update_version_in_buildfile(dependency, buildfile, previous_req,
                                      requirement)
        updated_content =
          buildfile.content.gsub(
            original_buildfile_declaration(dependency, previous_req),
            updated_buildfile_declaration(
              dependency,
              previous_req,
              requirement
            )
          )

        if updated_content == buildfile.content
          raise "Expected content to change!"
        end

        updated_file(file: buildfile, content: updated_content)
      end

      def original_buildfile_declaration(dependency, requirement)
        # This implementation is limited to declarations that appear on a
        # single line.
        buildfile = buildfiles.find { |f| f.name == requirement.fetch(:file) }
        buildfile.content.lines.find do |line|
          line = evaluate_properties(line, buildfile)
          line = line.gsub(%r{(?<=^|\s)//.*$}, "")

          if dependency.name.include?(":")
            next false unless line.include?(dependency.name.split(":").first)
            next false unless line.include?(dependency.name.split(":").last)
          else
            name_regex = /id\s+['"]#{Regexp.quote(dependency.name)}['"]/
            next false unless line.match?(name_regex)
          end

          line.include?(requirement.fetch(:requirement))
        end
      end

      def evaluate_properties(string, buildfile)
        result = string.dup

        string.scan(Gradle::FileParser::PROPERTY_REGEX) do
          prop_name = Regexp.last_match.named_captures.fetch("property_name")
          property_value = property_value_finder.property_value(
            property_name: prop_name,
            callsite_buildfile: buildfile
          )
          next unless property_value

          result.sub!(Regexp.last_match.to_s, property_value)
        end

        result
      end

      def property_value_finder
        @property_value_finder ||=
          Gradle::FileParser::PropertyValueFinder.
          new(dependency_files: dependency_files)
      end

      def updated_buildfile_declaration(dependency, previous_req, requirement)
        original_req_string = previous_req.fetch(:requirement)

        original_buildfile_declaration(dependency, previous_req).gsub(
          original_req_string,
          requirement.fetch(:requirement)
        )
      end

      def buildfiles
        @buildfiles ||= dependency_files.reject(&:support_file?)
      end
    end
  end
end

Dependabot::FileUpdaters.register("gradle", Dependabot::Gradle::FileUpdater)
