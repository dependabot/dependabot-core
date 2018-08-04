# frozen_string_literal: true

require "dependabot/file_updaters/elm/elm_package"

module Dependabot
  module FileUpdaters
    module Elm
      class ElmPackage
        class ElmPackageUpdater
          def initialize(elm_package_file:, dependencies:)
            @elm_package_file = elm_package_file
            @dependencies = dependencies
          end

          def updated_elm_package_file_content
            dependencies.
              select { |dep| requirement_changed?(elm_package_file, dep) }.
              reduce(elm_package_file.content.dup) do |content, dep|
                updated_content = content

                updated_content = update_requirement(
                  content: updated_content,
                  filename: elm_package_file.name,
                  dependency: dep
                )

                if content == updated_content
                  raise "Expected content to change!"
                end

                updated_content
              end
          end

          private

          attr_reader :elm_package_file, :dependencies

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
end
