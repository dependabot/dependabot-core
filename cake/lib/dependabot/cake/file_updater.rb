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
        updated_files = []

        dependency_files.each do |file|
          next unless requirement_changed?(file, dependency)

          updated_files <<
            updated_file(
              file: file,
              content: updated_cake_file_content(file)
            )
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def dependency
        # cake files will only ever be updating a single dependency
        dependencies.first
      end

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No Cake file!"
      end

      def updated_cake_file_content(file)
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

        raise "Expected content to change!" if updated_content == file.content

        updated_content
      end

      def supported_scheme?(scheme)
        %w(dotnet nuget).include?(scheme)
      end
    end
  end
end

Dependabot::FileUpdaters.register("cake", Dependabot::Cake::FileUpdater)
