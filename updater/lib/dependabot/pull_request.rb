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

      sig do
        params(
          name: String,
          version: T.nilable(String),
          removed: T::Boolean,
          directory: T.nilable(String)
        ).void
      end
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
          removed: removed? || nil,
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

    sig { returns(T.nilable(Integer)) }
    attr_reader :pr_number

    sig { params(attributes: T::Hash[Symbol, T.untyped]).returns(T::Array[Dependabot::PullRequest]) }
    def self.create_from_job_definition(attributes)
      attributes.fetch(:existing_pull_requests).map do |pr|
        case pr
        when Array
          pr_number = pr.first["pr-number"]
        when Hash
          pr_number = pr["pr-number"]
          pr = pr["dependencies"] # now pr becomes the dependencies array from the pr
        end

        dependencies =
          pr.map do |dep|
            Dependency.new(
              name: dep.fetch("dependency-name"),
              version: dep.fetch("dependency-version", nil),
              removed: dep.fetch("dependency-removed", false),
              directory: dep.fetch("directory", nil)
            )
          end

        new(dependencies, pr_number: pr_number)
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

    sig { params(dependencies: T::Array[PullRequest::Dependency], pr_number: T.nilable(Integer)).void }
    def initialize(dependencies, pr_number: nil)
      @dependencies = dependencies
      @pr_number = pr_number
    end

    sig { params(other: PullRequest).returns(T::Boolean) }
    def ==(other)
      if using_directory? && other.using_directory?
        dependencies_match?(dependencies, other.dependencies, compare_directory: true)
      else
        dependencies_match?(dependencies, other.dependencies, compare_directory: false)
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

    private

    sig do
      params(
        deps1: T::Array[Dependency],
        deps2: T::Array[Dependency],
        compare_directory: T::Boolean
      ).returns(T::Boolean)
    end
    def dependencies_match?(deps1, deps2, compare_directory:)
      return false unless deps1.length == deps2.length

      # Sort both arrays by name for consistent comparison
      sorted1 = deps1.sort_by(&:name)
      sorted2 = deps2.sort_by(&:name)

      sorted1.each_with_index do |dep1, index|
        dep2 = sorted2[index]
        return false unless dep2
        return false unless dependencies_equal?(dep1, dep2, compare_directory: compare_directory)
      end

      true
    end

    sig { params(dep1: Dependency, dep2: Dependency, compare_directory: T::Boolean).returns(T::Boolean) }
    def dependencies_equal?(dep1, dep2, compare_directory:)
      return false unless dep1.name == dep2.name
      return false if compare_directory && dep1.directory != dep2.directory
      return false unless dep1.removed? == dep2.removed?

      # If either dependency has a nil version, consider them equal by name only
      # This allows pending PRs without computed versions to match new updates
      return true if dep1.version.nil? || dep2.version.nil?

      # Otherwise, versions must match exactly
      dep1.version == dep2.version
    end
  end
end
