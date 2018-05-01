# frozen_string_literal: true

require "nokogiri"
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Java
      class Gradle < Dependabot::FileUpdaters::Base
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

        def original_buildfile_declaration(dependency, requirement)
          # This implementation is limited to declarations that appear on a
          # single line.
          buildfile = buildfiles.find { |f| f.name == requirement.fetch(:file) }
          buildfile.content.lines.find do |line|
            next false unless line.include?(dependency.name.split(":").first)
            next false unless line.include?(dependency.name.split(":").last)
            line.include?(requirement.fetch(:requirement))
          end
        end

        def updated_buildfile_declaration(dependency, previous_req, requirement)
          original_req_string = previous_req.fetch(:requirement)

          original_buildfile_declaration(dependency, previous_req).gsub(
            original_req_string,
            requirement.fetch(:requirement)
          )
        end

        def buildfiles
          @buildfiles ||=
            dependency_files.select { |f| f.name.end_with?("build.gradle") }
        end
      end
    end
  end
end
