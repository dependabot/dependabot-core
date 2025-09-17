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

      sig { returns(T.nilable(Integer)) }
      attr_reader :pr_number

      sig do
        params(name: String, version: T.nilable(String), removed: T::Boolean, directory: T.nilable(String),
               pr_number: T.nilable(Integer)).void
      end
      def initialize(name:, version:, removed: false, directory: nil, pr_number: nil)
        @name = name
        @version = version
        @removed = removed
        @directory = directory
        @pr_number = pr_number
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          name: name,
          version: version,
          removed: removed? || nil,
          directory: directory,
          pr_number: pr_number
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
              directory: dep.fetch("directory", nil),
              pr_number: dep.fetch("pr_number", nil)&.to_i
            )
          end
        )
      end
    end

    sig { params(updated_dependencies: T::Array[Dependabot::Dependency]).returns(Dependabot::PullRequest) }
    def self.create_from_updated_dependencies(updated_dependencies)
      new(
        updated_dependencies.filter_map do |dep|
          Dependency.new(
            name: dep.name,
            version: dep.version,
            removed: dep.removed?,
            directory: dep.directory
          )
        end
      )
    end

    sig { params(dependencies: T::Array[PullRequest::Dependency]).void }
    def initialize(dependencies)
      @dependencies = dependencies
    end

    sig { params(other: PullRequest).returns(T::Boolean) }
    def ==(other)
      if using_directory? && other.using_directory?
        dependencies.to_set(&:to_h) == other.dependencies.to_set(&:to_h)
      else
        dependencies.to_set { |dep| dep.to_h.except(:directory) } ==
          other.dependencies.to_set { |dep| dep.to_h.except(:directory) }
      end
    end

    sig { params(name: String, version: String).returns(T::Boolean) }
    def contains_dependency?(name, version)
      dependencies.any? { |dep| dep.name == name && dep.version == version }
    end

    sig { returns(T::Boolean) }
    def using_directory?
      dependencies.all? { |dep| !!dep.directory }
    end
  end
end
