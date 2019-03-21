# frozen_string_literal: true

require "toml-rb"
require "dependabot/python/file_updater"

module Dependabot
  module Python
    class FileUpdater
      class PipfileManifestUpdater
        def initialize(dependencies:, manifest:)
          @dependencies = dependencies
          @manifest = manifest
        end

        def updated_manifest_content
          dependencies.
            select { |dep| requirement_changed?(dep) }.
            reduce(manifest.content.dup) do |content, dep|
              updated_requirement =
                dep.requirements.find { |r| r[:file] == manifest.name }.
                fetch(:requirement)

              old_req =
                dep.previous_requirements.
                find { |r| r[:file] == manifest.name }.
                fetch(:requirement)

              updated_content =
                content.gsub(declaration_regex(dep)) do |line|
                  line.gsub(old_req, updated_requirement)
                end

              raise "Content did not change!" if content == updated_content

              updated_content
            end
        end

        private

        attr_reader :dependencies, :manifest

        def declaration_regex(dep)
          escaped_name = Regexp.escape(dep.name).gsub("\\-", "[-_.]")
          /(?:^|["'])#{escaped_name}["']?\s*=.*$/i
        end

        def requirement_changed?(dependency)
          changed_requirements =
            dependency.requirements - dependency.previous_requirements

          changed_requirements.any? { |f| f[:file] == manifest.name }
        end
      end
    end
  end
end
