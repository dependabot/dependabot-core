# typed: true
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

        attr_reader :dependencies
        attr_reader :dependency_files
        attr_reader :credentials

        def initialize(dependencies:, dependency_files:, credentials:, index_urls:nil)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @index_urls = index_urls
        end

        def updated_dependency_files
          @updated_dependency_files ||= fetch_updated_dependency_files
        end

        private

        def dependency
          # For now, we'll only ever be updating a single dependency
          dependencies.first
        end

        def fetch_updated_dependency_files
          reqs = dependency.requirements.zip(dependency.previous_requirements)

          reqs.filter_map do |(new_req, old_req)|
            next if new_req == old_req

            file = get_original_file(new_req.fetch(:file)).dup
            updated_content =
              updated_requirement_or_setup_file_content(new_req, old_req)
            next if updated_content == file.content

            file.content = updated_content
            file
          end
        end

        def updated_requirement_or_setup_file_content(new_req, old_req)
          original_file = get_original_file(new_req.fetch(:file))
          raise "Could not find a dependency file for #{new_req}" unless original_file

          RequirementReplacer.new(
            content: original_file.content,
            dependency_name: dependency.name,
            old_requirement: old_req.fetch(:requirement),
            new_requirement: new_req.fetch(:requirement),
            new_hash_version: dependency.version,
            index_urls: index_urls
          ).updated_content
        end

        def get_original_file(filename)
          dependency_files.find { |f| f.name == filename }
        end
      end
    end
  end
end
