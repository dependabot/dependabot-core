# typed: strong
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

      sig { params(hash: T::Hash[String, Object]).returns(Dependency) }
      def self.from_hash(hash)
        new(
          name: required_string(hash, "dependency-name"),
          version: optional_string(hash["dependency-version"], "dependency-version"),
          removed: boolean_with_default(hash, "dependency-removed", false),
          directory: optional_string(hash["directory"], "directory")
        )
      end

      sig { returns(T::Hash[Symbol, T.any(String, T::Boolean)]) }
      def to_h
        details = T.let({ name: name }, T::Hash[Symbol, T.any(String, T::Boolean)])
        parsed_version = version
        details[:version] = parsed_version if parsed_version
        details[:removed] = true if removed?
        parsed_directory = directory
        details[:directory] = parsed_directory if parsed_directory
        details
      end

      sig { returns(T::Boolean) }
      def removed?
        removed
      end

      sig { params(other: Object).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(Dependency)

        to_h == other.to_h
      end

      private

      sig { params(hash: T::Hash[String, Object], key: String).returns(String) }
      def self.required_string(hash, key)
        value = hash.fetch(key)
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end
      private_class_method :required_string

      sig { params(value: T.nilable(Object), key: String).returns(T.nilable(String)) }
      def self.optional_string(value, key)
        return if value.nil?
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end
      private_class_method :optional_string

      sig do
        params(
          hash: T::Hash[String, Object],
          key: String,
          default: T::Boolean
        ).returns(T::Boolean)
      end
      def self.boolean_with_default(hash, key, default)
        value = hash.fetch(key, default)
        return value if value == true || value == false

        raise TypeError, "#{key} must be a boolean"
      end
      private_class_method :boolean_with_default

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

    sig { params(attributes: T::Hash[Symbol, Object]).returns(T::Array[Dependabot::PullRequest]) }
    def self.create_from_job_definition(attributes)
      pull_requests = attributes.fetch(:existing_pull_requests)
      raise TypeError, "existing pull requests must be an array" unless pull_requests.is_a?(Array)

      pull_requests.map { |pull_request| from_job_value(T.cast(pull_request, Object)) }
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

    sig { params(other: Object).returns(T::Boolean) }
    def ==(other)
      return false unless other.is_a?(PullRequest)

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

    sig { params(value: Object).returns(PullRequest) }
    def self.from_job_value(value)
      case value
      when Array
        first_dependency = T.cast(value.first, Object)
        raise TypeError, "pull request dependencies must not be empty" if first_dependency.nil?

        first_hash = string_hash(first_dependency, "pull request dependency")
        new(
          dependency_array(value),
          pr_number: optional_integer(first_hash["pr-number"], "pr-number")
        )
      when Hash
        pull_request = string_hash(value, "pull request")
        new(
          dependency_array(pull_request.fetch("dependencies")),
          pr_number: optional_integer(pull_request["pr-number"], "pr-number")
        )
      else
        raise TypeError, "pull request must be an array or hash"
      end
    end
    private_class_method :from_job_value

    sig { params(value: Object).returns(T::Array[Dependency]) }
    def self.dependency_array(value)
      raise TypeError, "pull request dependencies must be an array" unless value.is_a?(Array)

      value.map do |dependency|
        Dependency.from_hash(string_hash(T.cast(dependency, Object), "pull request dependency"))
      end
    end
    private_class_method :dependency_array

    sig { params(value: Object, name: String).returns(T::Hash[String, Object]) }
    def self.string_hash(value, name)
      raise TypeError, "#{name} must be a hash" unless value.is_a?(Hash)

      result = T.let({}, T::Hash[String, Object])
      value.each do |raw_key, raw_value|
        key = T.cast(raw_key, Object)
        raise TypeError, "#{name} keys must be strings" unless key.is_a?(String)

        result[key] = T.cast(raw_value, Object)
      end
      result
    end
    private_class_method :string_hash

    sig { params(value: T.nilable(Object), name: String).returns(T.nilable(Integer)) }
    def self.optional_integer(value, name)
      return if value.nil?
      raise TypeError, "#{name} must be an integer" unless value.is_a?(Integer)

      value
    end
    private_class_method :optional_integer
  end
end
