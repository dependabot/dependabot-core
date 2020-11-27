# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module Cake
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [/.cake$/]
      end

      def updated_dependency_files
        updated_files = dependency_files.dup

        # Loop through each of the changed requirements, applying changes to
        # all files for that change.
        dependencies.each do |dependency|
          updated_files = update_files_for_dependency(
            files: updated_files,
            dependency: dependency
          )
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No Cake file!"
      end

      def update_files_for_dependency(files:, dependency:)
        # The UpdateChecker ensures the order of requirements is preserved
        # when updating, so we can zip them together in new/old pairs.
        reqs = dependency.
               requirements.
               zip(dependency.previous_requirements).
               reject { |new_req, old_req| new_req == old_req }

        # Loop through each changed requirement and update the files
        reqs.each do |new_req, old_req|
          raise "Bad req match" unless new_req[:file] == old_req[:file]
          next if new_req[:requirement] == old_req[:requirement]

          file = files.find { |f| f.name == new_req.fetch(:file) }

          files = update_declaration(files, dependency, file)
        end

        files
      end

      def update_declaration(files, dependency, file)
        files = files.dup
        updated_content = updated_cake_file_content(dependency, file)

        raise "Expected content to change!" if updated_content == file.content

        files[files.index(file)] =
          updated_file(file: file, content: updated_content)
        files
      end

      def updated_cake_file_content(dependency, file)
        updated_content = file.content

        file.content.each_line do |line|
          directive = Directives.parse_cake_directive_from(line)
          next if directive.nil?
          next unless supported_scheme?(directive.scheme)
          next unless directive.query[:package] == dependency.name

          new_declaration = line.gsub("version=#{dependency.previous_version}",
                                      "version=#{dependency.version}")

          updated_content = updated_content.gsub(line, new_declaration)
        end

        updated_content
      end

      def supported_scheme?(scheme)
        %w(dotnet nuget).include?(scheme)
      end
    end
  end
end

Dependabot::FileUpdaters.register("cake", Dependabot::Cake::FileUpdater)
