# frozen_string_literal: true

require "dependabot/file_updaters/php/composer"

module Dependabot
  module FileUpdaters
    module Php
      class Composer
        class ManifestUpdater
          def initialize(dependencies:, manifest:)
            @dependencies = dependencies
            @manifest = manifest
          end

          def updated_manifest_content
            file = manifest

            updated_content =
              dependencies.
              select { |dep| requirement_changed?(file, dep) }.
              reduce(file.content.dup) do |content, dep|
                updated_req =
                  dep.requirements.find { |r| r[:file] == file.name }.
                  fetch(:requirement)

                old_req =
                  dep.previous_requirements.find { |r| r[:file] == file.name }.
                  fetch(:requirement)

                regex =
                  /
                    "#{Regexp.escape(dep.name)}"\s*:\s*
                    "#{Regexp.escape(old_req)}"
                  /x

                updated_content = content.gsub(regex) do |declaration|
                  declaration.gsub(%("#{old_req}"), %("#{updated_req}"))
                end

                if content == updated_content
                  raise "Expected content to change!"
                end

                updated_content
              end
          end

          private

          attr_reader :dependencies, :manifest

          def requirement_changed?(file, dependency)
            changed_requirements =
              dependency.requirements - dependency.previous_requirements

            changed_requirements.any? { |f| f[:file] == file.name }
          end
        end
      end
    end
  end
end
