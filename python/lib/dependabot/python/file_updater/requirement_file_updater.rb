# frozen_string_literal: true

require "dependabot/python/requirement_parser"
require "dependabot/python/file_updater"
require "dependabot/shared_helpers"
require "dependabot/python/native_helpers"

module Dependabot
  module Python
    class FileUpdater
      class RequirementFileUpdater
        require_relative "requirement_replacer"

        attr_reader :dependencies, :dependency_files, :credentials

        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
        end

        def updated_dependency_files
          return @updated_dependency_files if @update_already_attempted

          @update_already_attempted = true
          @updated_dependency_files ||= fetch_updated_dependency_files
        end

        private

        def dependency
          # For now, we'll only ever be updating a single dependency
          dependencies.first
        end

        def fetch_updated_dependency_files
          reqs = dependency.requirements.zip(dependency.previous_requirements)

          reqs.map do |(new_req, old_req)|
            next if new_req == old_req

            file = get_original_file(new_req.fetch(:file)).dup
            updated_content =
              updated_requirement_or_setup_file_content(new_req, old_req)
            next if updated_content == file.content

            file.content = updated_content
            file
          end.compact
        end

        def updated_requirement_or_setup_file_content(new_req, old_req)
          content = get_original_file(new_req.fetch(:file)).content

          RequirementReplacer.new(
            content: content,
            dependency_name: dependency.name,
            old_requirement: old_req.fetch(:requirement),
            new_requirement: new_req.fetch(:requirement),
            new_hash_version: dependency.version
          ).updated_content
        end

        def get_original_file(filename)
          dependency_files.find { |f| f.name == filename }
        end
      end
    end
  end
end
