# typed: strict
# frozen_string_literal: true

require "dependabot/python/requirement_parser"
require "dependabot/python/file_updater"
require "dependabot/shared_helpers"
require "dependabot/python/native_helpers"
require "sorbet-runtime"

module Dependabot
  module Python
    class FileUpdater
      class RequirementFileUpdater
        extend T::Sig

        require_relative "requirement_replacer"

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            index_urls: T.nilable(T::Array[String])
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:, index_urls: nil)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @index_urls = index_urls
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_dependency_files
          @updated_dependency_files ||= T.let(
            fetch_updated_dependency_files,
            T.nilable(T::Array[DependencyFile])
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        def dependency
          # For now, we'll only ever be updating a single dependency
          T.must(dependencies.first)
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def fetch_updated_dependency_files
          reqs = dependency.requirements.zip(dependency.previous_requirements || [])

          reqs.filter_map do |(new_req, old_req)|
            next if new_req == old_req

            file = get_original_file(new_req.fetch(:file)).dup
            updated_content =
              updated_requirement_or_setup_file_content(new_req, old_req)
            next if updated_content == file&.content

            file&.content = updated_content
            file
          end
        end

        sig do
          params(
            new_req: T::Hash[Symbol, T.untyped],
            old_req: T.nilable(T::Hash[Symbol, T.untyped])
          ).returns(T.nilable(String))
        end
        def updated_requirement_or_setup_file_content(new_req, old_req)
          original_file = get_original_file(new_req.fetch(:file))
          raise "Could not find a dependency file for #{new_req}" unless original_file

          original_content = original_file.content
          return original_content if original_content.nil?

          RequirementReplacer.new(
            content: original_content,
            dependency_name: dependency.name,
            old_requirement: old_req&.fetch(:requirement),
            new_requirement: new_req.fetch(:requirement),
            new_hash_version: dependency.version,
            index_urls: @index_urls
          ).updated_content
        end

        sig do
          params(filename: String)
            .returns(T.nilable(Dependabot::DependencyFile))
        end
        def get_original_file(filename)
          dependency_files.find { |f| f.name == filename }
        end
      end
    end
  end
end
