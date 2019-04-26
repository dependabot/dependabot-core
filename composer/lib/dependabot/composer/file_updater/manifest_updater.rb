# frozen_string_literal: true

require "dependabot/composer/file_updater"

module Dependabot
  module Composer
    class FileUpdater
      class ManifestUpdater
        def initialize(dependencies:, manifest:)
          @dependencies = dependencies
          @manifest = manifest
        end

        def updated_manifest_content
          dependencies.reduce(manifest.content.dup) do |content, dep|
            updated_content = content
            updated_requirements(dep).each do |new_req|
              old_req = old_requirement(dep, new_req).fetch(:requirement)
              updated_req = new_req.fetch(:requirement)

              regex =
                /
                  "#{Regexp.escape(dep.name)}"\s*:\s*
                  "#{Regexp.escape(old_req)}"
                /x

              updated_content = content.gsub(regex) do |declaration|
                declaration.gsub(%("#{old_req}"), %("#{updated_req}"))
              end

              raise "Expected content to change!" if content == updated_content
            end

            updated_content
          end
        end

        private

        attr_reader :dependencies, :manifest

        def new_requirements(dependency)
          dependency.requirements.select { |r| r[:file] == manifest.name }
        end

        def old_requirement(dependency, new_requirement)
          dependency.previous_requirements.
            select { |r| r[:file] == manifest.name }.
            find { |r| r[:groups] == new_requirement[:groups] }
        end

        def updated_requirements(dependency)
          new_requirements(dependency).
            reject { |r| dependency.previous_requirements.include?(r) }
        end

        def requirement_changed?(file, dependency)
          changed_requirements =
            dependency.requirements - dependency.previous_requirements

          changed_requirements.any? { |f| f[:file] == file.name }
        end
      end
    end
  end
end
