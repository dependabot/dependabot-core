# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/credential"
require "dependabot/ecosystem"

module Dependabot
  module FileParsers
    class Base
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      sig { returns(T.nilable(String)) }
      attr_reader :repo_contents_path

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T.nilable(Dependabot::Source)) }
      attr_reader :source

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :options

      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          source: T.nilable(Dependabot::Source),
          repo_contents_path: T.nilable(String),
          credentials: T::Array[Dependabot::Credential],
          reject_external_code: T::Boolean,
          options: T::Hash[Symbol, T.untyped]
        )
          .void
      end
      def initialize(dependency_files:, source:, repo_contents_path: nil,
                     credentials: [], reject_external_code: false, options: {})
        @dependency_files = dependency_files
        @repo_contents_path = repo_contents_path
        @credentials = credentials
        @source = source
        @reject_external_code = reject_external_code
        @options = options

        check_required_files
      end

      sig { abstract.returns(T::Array[Dependabot::Dependency]) }
      def parse; end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def package_manager
        nil
      end

      private

      sig { abstract.void }
      def check_required_files; end

      sig { params(filename: String).returns(T.nilable(Dependabot::DependencyFile)) }
      def get_original_file(filename)
        dependency_files.find { |f| f.name == filename }
      end
    end
  end
end
