# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/requirement_parser"
require "dependabot/python/file_updater"
require "dependabot/shared_helpers"
require "dependabot/python/native_helpers"

module Dependabot
  module Python
    class FileUpdater
      class RequirementFileUpdater
        extend T::Sig

        require_relative "requirement_replacer"

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            index_urls: T.nilable(T::Array[T.nilable(String)])
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:, index_urls: nil)
          @dependencies = T.let(dependencies, T::Array[Dependabot::Dependency])
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
          @index_urls = T.let(index_urls, T.nilable(T::Array[T.nilable(String)]))
          @updated_dependency_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_dependency_files
          @updated_dependency_files ||= fetch_updated_dependency_files
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

            file = T.must(get_original_file(new_req.fetch(:file))).dup
            updated_content =
              updated_requirement_or_setup_file_content(new_req, old_req)
            next if updated_content == file.content

            file.content = updated_content
            file
          end
        end

        sig do
          params(
            new_req: T::Hash[Symbol, T.untyped],
            old_req: T.nilable(T::Hash[Symbol, T.untyped])
          ).returns(String)
        end
        def updated_requirement_or_setup_file_content(new_req, old_req)
          original_file = get_original_file(new_req.fetch(:file))
          raise "Could not find a dependency file for #{new_req}" unless original_file

          RequirementReplacer.new(
            content: T.must(original_file.content),
            dependency_name: dependency.name,
            old_requirement: old_req&.fetch(:requirement),
            new_requirement: new_req.fetch(:requirement),
            new_hash_version: dependency.version,
            index_urls: @index_urls
          ).updated_content
        end

        sig { params(filename: String).returns(T.nilable(Dependabot::DependencyFile)) }
        def get_original_file(filename)
          dependency_files.find { |f| f.name == filename }
        end
      end
    end
  end
end
