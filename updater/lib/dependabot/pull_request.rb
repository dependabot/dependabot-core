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
        @directory = T.let(normalize_directory(directory), T.nilable(String))
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

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(Dependency)

        to_h == other.to_h
      end

      private

      sig { params(directory: T.nilable(String)).returns(T.nilable(String)) }
      def normalize_directory(directory)
        return nil if directory.nil?

        directory.to_s
                 .sub(%r{/*\Z}, "")    # remove trailing slashes
                 .sub(%r{\A/*}, "/")   # prefix with a single slash
                 .sub(%r{\A/\Z}, "/.") # use `/.` as root
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
            PullRequest::Dependency.new(
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
        dependencies.to_set(&:to_h) == other.dependencies.to_set(&:to_h)
      else
        dependencies.to_set { |dep| dep.to_h.except(:directory) } ==
          other.dependencies.to_set { |dep| dep.to_h.except(:directory) }
      end
    end

    sig { params(name: String, version: String, dir: String).returns(T::Boolean) }
    def contains_dependency?(name, version, dir)
      dependency = PullRequest::Dependency.new(name:, version:, directory: dir)
      dependencies.any?(dependency)
    end

    sig { returns(T::Boolean) }
    def using_directory?
      dependencies.all? { |dep| !!dep.directory }
    end
  end
end
