# frozen_string_literal: true

require "dependabot/elm/file_updater"

module Dependabot
  module Elm
    class FileUpdater
      class ElmJsonUpdater
        def initialize(elm_json_file:, dependencies:)
          @elm_json_file = elm_json_file
          @dependencies = dependencies
        end

        def updated_content
          dependencies.
            select { |dep| requirement_changed?(elm_json_file, dep) }.
            reduce(elm_json_file.content.dup) do |content, dep|
              updated_content = content

              updated_content = update_requirement(
                content: updated_content,
                filename: elm_json_file.name,
                dependency: dep
              )

              next updated_content unless content == updated_content

              raise "Expected content to change!"
            end
        end

        private

        attr_reader :elm_json_file, :dependencies

        def requirement_changed?(file, dependency)
          changed_requirements =
            dependency.requirements - dependency.previous_requirements

          changed_requirements.any? { |f| f[:file] == file.name }
        end

        def update_requirement(content:, filename:, dependency:)
          updated_req =
            dependency.requirements.
            find { |r| r.fetch(:file) == filename }.
            fetch(:requirement)

          old_req =
            dependency.previous_requirements.
            find { |r| r.fetch(:file) == filename }.
            fetch(:requirement)

          return content unless old_req

          dep = dependency
          regex =
            /"#{Regexp.quote(dep.name)}"\s*:\s+"#{Regexp.quote(old_req)}"/

          content.gsub(regex) do |declaration|
            declaration.gsub(%("#{old_req}"), %("#{updated_req}"))
          end
        end
      end
    end
  end
end
