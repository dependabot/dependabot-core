# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/credential"

module Dependabot
  module FileUpdaters
    class Base
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(T::Array[Dependabot::Dependency]) }
      attr_reader :dependencies

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      sig { returns(T.nilable(String)) }
      attr_reader :repo_contents_path

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :options

      sig { overridable.params(allowlist_enabled: T::Boolean).returns(T::Array[Regexp]) }
      def self.updated_files_regex(allowlist_enabled = false)
        raise NotImplementedError
      end

      sig do
        params(
          dependencies: T::Array[Dependabot::Dependency],
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          repo_contents_path: T.nilable(String),
          options: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(dependencies:, dependency_files:, credentials:, repo_contents_path: nil, options: {})
        @dependencies = dependencies
        @dependency_files = dependency_files
        @repo_contents_path = repo_contents_path
        @credentials = credentials
        @options = options

        check_required_files
      end

      sig { overridable.returns(T::Array[::Dependabot::DependencyFile]) }
      def updated_dependency_files
        raise NotImplementedError
      end

      private

      sig { overridable.void }
      def check_required_files
        raise NotImplementedError
      end

      sig { params(filename: String).returns(T.nilable(Dependabot::DependencyFile)) }
      def get_original_file(filename)
        dependency_files.find { |f| f.name == filename }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def file_changed?(file)
        dependencies.any? { |dep| requirement_changed?(file, dep) }
      end

      sig { params(file: Dependabot::DependencyFile, dependency: Dependabot::Dependency).returns(T::Boolean) }
      def requirement_changed?(file, dependency)
        changed_requirements = dependency.requirements - T.must(dependency.previous_requirements)

        changed_requirements.any? { |f| f[:file] == file.name }
      end

      sig { params(file: Dependabot::DependencyFile, content: String).returns(Dependabot::DependencyFile) }
      def updated_file(file:, content:)
        updated_file = file.dup
        updated_file.content = content
        updated_file
      end
    end
  end
end
