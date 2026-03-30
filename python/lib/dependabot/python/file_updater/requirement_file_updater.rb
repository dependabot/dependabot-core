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

          updated_contents = T.let({}, T::Hash[String, String])

          reqs.each do |(new_req, old_req)|
            next if new_req == old_req

            filename = new_req.fetch(:file)
            content = updated_contents[filename] || T.must(T.must(get_original_file(filename)).content)
            updated_contents[filename] = updated_requirement_or_setup_file_content(content, new_req, old_req)
          rescue RuntimeError => e
            raise unless e.message.start_with?("Declaration not found for")
          end

          updated_contents.filter_map do |filename, content|
            file = T.must(get_original_file(filename)).dup
            next if content == T.must(file.content)

            file.content = content
            file
          end
        end

        sig do
          params(
            content: String,
            new_req: T::Hash[Symbol, T.untyped],
            old_req: T.nilable(T::Hash[Symbol, T.untyped])
          ).returns(String)
        end
        def updated_requirement_or_setup_file_content(content, new_req, old_req)
          RequirementReplacer.new(
            content: content,
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
