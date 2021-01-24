# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Helm
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [
          /^Chart\.yaml$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        [*chart_files].each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(
              file: file,
              content: update_content(file)
            )
        end

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def check_required_files
        return if [*chart_files].any?
        return if chart_yaml

        raise "No Chart.yaml!"
      end

      def chart_files
        dependency_files.select do |f|
          f.name == "Chart.yaml"
        end
      end

      def dependency
        # Helm charts will only ever be updating a single dependency
        dependencies.first
      end

      def update_content(file)
        content = file.content.dup

        dependency.requirements.each do |req|
          next unless req.fetch(:file) == file.name

          case req[:file]
          when "Chart.yaml"
            return update_chart_file(dependency.name, req[:requirement], content)
          end
        end
      end

      def update_chart_file(name, version, content)
        parsed = Psych.load(content)
        parsed["dependencies"].each_with_index do |dep, index|
          parsed["dependencies"][index]["version"] = version if name == dep.fetch("name")
        end

        parsed["generated"] = "\"#{parsed['generated']}\"" if parsed["generated"]
        Psych.dump(parsed).gsub("---\n", "")
      end
    end
  end
end

Dependabot::FileUpdaters.register("helm", Dependabot::Helm::FileUpdater)
