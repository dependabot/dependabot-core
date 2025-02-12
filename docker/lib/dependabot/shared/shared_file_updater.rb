# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"
require "sorbet-runtime"

module Dependabot
  module Shared
    class SharedFileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig
      extend T::Helpers

      protected

      sig { params(file: Dependabot::DependencyFile, dependency: Dependabot::Dependency).returns(T::Boolean) }
      def requirement_changed?(file, dependency)
        changed_requirements =
          dependency.requirements - dependency.previous_requirements

        changed_requirements.any? { |f| f[:file] == file.name }
      end

      sig { params(source: T::Hash[Symbol, T.nilable(String)]).returns(T::Boolean) }
      def specified_with_tag?(source)
        !source[:tag].nil?
      end

      sig { params(source: T::Hash[Symbol, T.nilable(String)]).returns(T::Boolean) }
      def specified_with_digest?(source)
        !source[:digest].nil?
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def requirements(file)
        T.must(dependency).requirements
          .select { |r| r[:file] == file.name }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
      def previous_requirements(file)
        T.must(dependency).previous_requirements
          &.select { |r| r[:file] == file.name }
      end

      sig { params(source: T::Hash[Symbol, T.nilable(String)]).returns(T.nilable(String)) }
      def private_registry_url(source)
        source[:registry]
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
      def sources(file)
        requirements(file).map { |r| r.fetch(:source) }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(T::Array[T::Hash[Symbol, T.nilable(String)]])) }
      def previous_sources(file)
        previous_requirements(file)&.map { |r| r.fetch(:source) }
      end

      sig { returns(T.nilable(Dependabot::Dependency)) }
      def dependency
        # Files will only ever be updating a single dependency
        dependencies.first
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No #{file_type}!"
      end

      private

      sig { abstract.returns(String) }
      def file_type
        raise NotImplementedError, "#{self.class.name} must implement #file_type"
      end
    end
  end
end
