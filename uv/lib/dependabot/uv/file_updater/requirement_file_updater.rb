# typed: strict
# frozen_string_literal: true

require "dependabot/uv/requirement_parser"
require "dependabot/uv/file_updater"
require "dependabot/shared_helpers"
require "dependabot/uv/native_helpers"
require "sorbet-runtime"

module Dependabot
  module Uv
    class FileUpdater
      class RequirementFileUpdater
        extend T::Sig

        require_relative "requirement_replacer"

        sig { returns(T::Array[Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig do
          params(
            dependencies: T::Array[Dependency],
            dependency_files: T::Array[DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            index_urls: T.nilable(T::Array[String])
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:, index_urls: nil)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @index_urls = index_urls
          @updated_dependency_files = T.let(nil, T.nilable(T::Array[DependencyFile]))
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_dependency_files
          @updated_dependency_files ||= fetch_updated_dependency_files
        end

        private

        sig { returns(T.nilable(Dependency)) }
        def dependency
          # For now, we'll only ever be updating a single dependency
          dependencies.first
        end

        sig { returns(T::Array[DependencyFile]) }
        def fetch_updated_dependency_files
          previous_requirements = T.must(dependency).previous_requirements || []
          reqs = T.must(dependency).requirements.zip(previous_requirements)

          reqs.filter_map do |(new_req, old_req)|
            next if new_req == old_req

            file = get_original_file(new_req.fetch(:file)).dup
            updated_content =
              updated_requirement_or_setup_file_content(new_req, T.must(old_req))
            next if updated_content == T.must(file).content

            T.must(file).content = updated_content
            file
          end
        end

        sig { params(new_req: T::Hash[Symbol, T.untyped], old_req: T::Hash[Symbol, T.untyped]).returns(String) }
        def updated_requirement_or_setup_file_content(new_req, old_req)
          original_file = get_original_file(new_req.fetch(:file))
          raise "Could not find a dependency file for #{new_req}" unless original_file

          RequirementReplacer.new(
            content: original_file.content,
            dependency_name: T.must(dependency).name,
            old_requirement: old_req.fetch(:requirement),
            new_requirement: new_req.fetch(:requirement),
            new_hash_version: T.must(dependency).version,
            index_urls: @index_urls
          ).updated_content
        end

        sig { params(filename: String).returns(T.nilable(DependencyFile)) }
        def get_original_file(filename)
          dependency_files.find { |f| f.name == filename }
        end
      end
    end
  end
end
