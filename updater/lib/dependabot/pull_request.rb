# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequest
    extend T::Sig

    class Dependency
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { returns(T.nilable(String)) }
      attr_reader :version

      sig { returns(T::Boolean) }
      attr_reader :removed

      sig { returns(T.nilable(String)) }
      attr_reader :directory

      sig { params(name: String, version: T.nilable(String), removed: T::Boolean, directory: T.nilable(String)).void }
      def initialize(name:, version:, removed: false, directory: nil)
        @name = name
        @version = version
        @removed = removed
        @directory = directory
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          name: name,
          version: version,
          removed: removed? ? true : nil,
          directory: directory
        }.compact
      end

      sig { returns(T::Boolean) }
      def removed?
        removed
      end
    end

    sig { returns(T::Array[Dependency]) }
    attr_reader :dependencies

    sig { params(attributes: T::Hash[Symbol, T.untyped]).returns(T::Array[Dependabot::PullRequest]) }
    def self.create_from_job_definition(attributes)
      attributes.fetch(:existing_pull_requests).map do |pr|
        new(
          pr.map do |dep|
            Dependency.new(
              name: dep.fetch("dependency-name"),
              version: dep.fetch("dependency-version", nil),
              removed: dep.fetch("dependency-removed", false),
              directory: dep.fetch("directory", nil)
            )
          end
        )
      end
    end

    sig { params(updated_dependencies: T::Array[Dependabot::Dependency]).returns(Dependabot::PullRequest) }
    def self.create_from_updated_dependencies(updated_dependencies)
      new(
        updated_dependencies.map do |dep|
          Dependency.new(
            name: dep.name,
            version: dep.version,
            removed: dep.removed?,
            directory: dep.directory
          )
        end.compact
      )
    end

    sig { params(dependencies: T::Array[PullRequest::Dependency]).void }
    def initialize(dependencies)
      @dependencies = dependencies
    end

    sig { params(other: PullRequest).returns(T::Boolean) }
    def ==(other)
      if using_directory? && other.using_directory?
        dependencies.map(&:to_h).to_set == other.dependencies.map(&:to_h).to_set
      else
        compare_without_directory?(other)
      end
    end

    sig { returns(T::Boolean) }
    def using_directory?
      dependencies.all? { |dep| !!dep.directory }
    end

    sig { params(name: String, version: String).returns(T::Boolean) }
    def contains_dependency?(name, version)
      dependencies.any? { |dep| dep.name == name && dep.version == version }
    end

    private

    sig { params(other: PullRequest).returns(T::Boolean) }
    def compare_without_directory?(other)
      return false unless dependencies.size == other.dependencies.size

      dependencies.map { |dep| dep.to_h.except(:directory) }.to_set ==
        other.dependencies.map { |dep| dep.to_h.except(:directory) }.to_set
    end
  end
end
