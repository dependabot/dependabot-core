# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Sbt
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [/^build\.sbt$/, %r{/build\.sbt$}]
      end

      def updated_dependency_files
        updated_files = buildfiles.dup

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
        raise "No build.sbt!" unless get_original_file("build.sbt")
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

          files[files.index(buildfile)] =
            update_version_in_buildfile(
              dependency,
              buildfile,
              old_req,
              new_req
            )
        end

        files
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

      def updated_buildfile_declaration(dependency, previous_req, requirement)
        original_req_string = previous_req.fetch(:requirement)

        original_buildfile_declaration(dependency, previous_req).
          gsub(original_req_string, requirement.fetch(:requirement))
      end

      def original_buildfile_declaration(dependency, requirement)
        buildfile = buildfiles.find { |f| f.name == requirement.fetch(:file) }

        if requirement[:metadata][:cross_scala_versions].any?
          name_as_appeared_in_file = name_minus_cross_scala_version(
            dependency, requirement[:metadata][:cross_scala_versions]
          )
        else
          name_as_appeared_in_file = dependency.name
        end

        group = name_as_appeared_in_file.split(":").first
        name = name_as_appeared_in_file.split(":").last

        name_regex =
          /\s+"#{Regexp.quote(group)}"\s+[%]+\s+"#{Regexp.quote(name)}"\s+/

        original_version = requirement.fetch(:requirement)

        buildfile.content.lines.find do |line|
          line.match?(name_regex) && line.include?(original_version)
        end
      end

      def name_minus_cross_scala_version(dependency, scala_versions)
        version = scala_versions.find { |v| dependency.name.include?(v) }
        dependency.name.sub("_#{version}", "")
      end

      def buildfiles
        @buildfiles ||= dependency_files.reject(&:support_file?)
      end
    end
  end
end

Dependabot::FileUpdaters.register("sbt", Dependabot::Sbt::FileUpdater)
