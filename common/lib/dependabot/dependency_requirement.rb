# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

module Dependabot
  class DependencyRequirement < T::ImmutableStruct
    extend T::Sig

    Key = T.type_alias { T.any(String, Symbol) }
    Group = T.type_alias { T.any(String, Symbol) }
    Details = T.type_alias { T::Hash[Key, Object] }

    REQUIRED_KEYS = T.let(%i(requirement file groups source).freeze, T::Array[Symbol])
    OPTIONAL_KEYS = T.let(%i(metadata).freeze, T::Array[Symbol])

    const :requirement, T.nilable(String)
    const :file, T.nilable(String)
    const :groups, T.nilable(T::Array[Group])
    const :source, T.nilable(Details)
    const :metadata, T.nilable(Details)
    const :unfixable, T::Boolean
    const :metadata_present, T::Boolean

    sig { params(hash: T::Hash[Key, T.anything]).returns(DependencyRequirement) }
    def self.from_hash(hash)
      values = symbolize_keys(hash)
      validate_keys(values)

      requirement, unfixable = parse_requirement(values.fetch(:requirement))

      new(
        requirement: requirement,
        file: parse_file(values.fetch(:file)),
        groups: parse_groups(values.fetch(:groups)),
        source: parse_details(values.fetch(:source), "source"),
        metadata: parse_details(values[:metadata], "metadata"),
        unfixable: unfixable,
        metadata_present: values.key?(:metadata)
      )
    end

    sig { returns(T::Boolean) }
    def unfixable?
      unfixable
    end

    sig { params(key: Key).returns(T.nilable(String)) }
    def source_string(key)
      details_string(source, key)
    end

    sig { params(key: Key).returns(T.nilable(String)) }
    def metadata_string(key)
      details_string(metadata, key)
    end

    sig { params(value: T.nilable(T.any(String, Symbol))).returns(DependencyRequirement) }
    def with_requirement(value)
      self.class.from_hash(to_h.merge(requirement: value))
    end

    sig { params(value: T.nilable(String)).returns(DependencyRequirement) }
    def with_file(value)
      self.class.from_hash(to_h.merge(file: value))
    end

    sig { params(value: T.nilable(T::Array[Group])).returns(DependencyRequirement) }
    def with_groups(value)
      self.class.from_hash(to_h.merge(groups: value))
    end

    sig { params(value: T.nilable(T::Hash[Key, T.anything])).returns(DependencyRequirement) }
    def with_source(value)
      self.class.from_hash(to_h.merge(source: value))
    end

    sig { params(value: T.nilable(T::Hash[Key, T.anything])).returns(DependencyRequirement) }
    def with_metadata(value)
      self.class.from_hash(to_h.merge(metadata: value))
    end

    sig { returns(T::Hash[Symbol, Object]) }
    def to_h
      result = T.let(
        {
          requirement: unfixable? ? :unfixable : requirement,
          file: file,
          groups: groups,
          source: source
        },
        T::Hash[Symbol, Object]
      )
      result[:metadata] = metadata if metadata_present
      result
    end

    sig { params(_state: T.nilable(Object)).returns(String) }
    def to_json(_state = nil)
      JSON.generate(to_h)
    end

    sig { params(other: Object).returns(T::Boolean) }
    def ==(other)
      other.is_a?(DependencyRequirement) && to_h == other.to_h
    end

    sig { params(other: Object).returns(T::Boolean) }
    def eql?(other)
      self == other
    end

    sig { returns(Integer) }
    def hash
      to_h.hash
    end

    sig { params(details: T.nilable(Details), key: Key).returns(T.nilable(String)) }
    def details_string(details, key)
      return unless details

      alternate_key = key.is_a?(String) ? key.to_sym : key.to_s
      value = details[key] || details[alternate_key]
      value if value.is_a?(String)
    end
    private :details_string

    class << self
      extend T::Sig

      private

      sig { params(hash: T::Hash[Key, T.anything]).returns(T::Hash[Symbol, Object]) }
      def symbolize_keys(hash)
        hash.each_with_object(T.let({}, T::Hash[Symbol, Object])) do |(raw_key, raw_value), result|
          key = T.let(raw_key, Object)
          raise TypeError, "requirement keys must be strings or symbols" unless key.is_a?(String) || key.is_a?(Symbol)

          result[key.to_sym] = T.cast(raw_value, Object)
        end
      end

      sig { params(values: T::Hash[Symbol, Object]).void }
      def validate_keys(values)
        missing_keys = REQUIRED_KEYS - values.keys
        unknown_keys = values.keys - REQUIRED_KEYS - OPTIONAL_KEYS

        unless missing_keys.empty?
          raise ArgumentError, "requirement must have the following required keys: #{REQUIRED_KEYS.join(', ')}"
        end
        return if unknown_keys.empty?

        raise ArgumentError,
              "each requirement must have the following required keys: #{REQUIRED_KEYS.join(', ')}; " \
              "unknown keys: #{unknown_keys.join(', ')}"
      end

      sig { params(value: Object).returns([T.nilable(String), T::Boolean]) }
      def parse_requirement(value)
        return [nil, false] if value.nil?
        return [value, false] if value.is_a?(String) && !value.empty?
        return [nil, true] if value == :unfixable
        raise ArgumentError, "blank strings must not be provided as requirements" if value == ""

        raise TypeError, "requirement must be a string, :unfixable, or nil"
      end

      sig { params(value: Object).returns(T.nilable(String)) }
      def parse_file(value)
        return value if value.nil? || value.is_a?(String)

        raise TypeError, "file must be a string or nil"
      end

      sig { params(value: Object).returns(T.nilable(T::Array[Group])) }
      def parse_groups(value)
        return if value.nil?
        raise TypeError, "groups must be an array of strings or symbols, or nil" unless value.is_a?(Array)

        groups = T.let(value, T::Array[Object])
        unless groups.all? { |entry| entry.is_a?(String) || entry.is_a?(Symbol) }
          raise TypeError, "groups must be an array of strings or symbols, or nil"
        end

        groups.map { |entry| T.cast(entry, Group) }.freeze
      end

      sig { params(value: T.nilable(Object), name: String).returns(T.nilable(Details)) }
      def parse_details(value, name)
        return if value.nil?
        raise TypeError, "#{name} must be a hash or nil" unless value.is_a?(Hash)

        hash = T.let(value, T::Hash[Object, Object])
        hash.each_with_object(T.let({}, Details)) do |(raw_key, raw_value), result|
          key = raw_key
          raise TypeError, "#{name} keys must be strings or symbols" unless key.is_a?(String) || key.is_a?(Symbol)

          result[key] = raw_value
        end.freeze
      end
    end

    private_class_method :new
  end
end
