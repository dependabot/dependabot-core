# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  # A single requirement entry within Dependency#requirements, e.g.:
  #
  #   {
  #     requirement: ">= 1.0, < 2.0",
  #     file: "Gemfile",
  #     groups: [:default],
  #     source: { type: "rubygems", url: "https://rubygems.org" },
  #     metadata: { property_name: "rails.version" } # optional
  #   }
  #
  # Subclasses Hash temporarily so existing call sites remain compatible while
  # they migrate to the typed readers and copy methods below.
  #
  # Wire compatibility: instances serialise to JSON exactly like the plain
  # hash they were created from, and compare equal (==/eql?/#hash) to plain
  # hashes with the same content, so existing comparisons, Array/Set
  # operations, and API payloads are unaffected.
  #
  # Note on Hash methods: in Ruby 3+, #merge, #dup and #compact preserve
  # this class, while #select, #reject, #except, #transform_values and
  # #to_h return plain Hash instances. Dependency#initialize re-wraps
  # whatever it is given, so both styles remain safe.
  class DependencyRequirement < Hash
    extend T::Sig
    extend T::Generic

    Key = T.type_alias { T.any(String, Symbol) }
    Group = T.type_alias { T.any(String, Symbol) }
    Details = T.type_alias { T::Hash[Key, Object] }

    # Keep the Hash bridge untyped until every caller has moved to readers.
    # rubocop:disable Sorbet/ForbidTUntyped
    K = type_member { { fixed: Symbol } }
    V = type_member { { fixed: T.untyped } }
    Elem = type_member { { fixed: [Symbol, T.untyped] } }
    # rubocop:enable Sorbet/ForbidTUntyped

    REQUIRED_KEYS = T.let(%i(requirement file groups source).freeze, T::Array[Symbol])
    OPTIONAL_KEYS = T.let(%i(metadata).freeze, T::Array[Symbol])

    sig do
      params(
        hash: T.any(
          DependencyRequirement,
          T::Hash[Key, T.anything]
        )
      ).returns(DependencyRequirement)
    end
    def self.create(hash)
      return from_hash(hash.to_h) if hash.is_a?(DependencyRequirement)

      from_hash(hash)
    end

    sig { params(hash: T::Hash[Key, T.anything]).returns(DependencyRequirement) }
    def self.from_hash(hash)
      values = symbolize_keys(hash)
      validate_keys(values)

      parsed_requirement = parse_requirement(values.fetch(:requirement))
      parsed_file = parse_file(values.fetch(:file))
      parsed_groups = parse_groups(values.fetch(:groups))
      parsed_source = parse_details(values.fetch(:source), "source")
      parsed_metadata = parse_details(values[:metadata], "metadata")

      normalized = T.let(
        {
          requirement: parsed_requirement,
          file: parsed_file,
          groups: parsed_groups,
          source: parsed_source
        },
        T::Hash[Symbol, Object]
      )
      normalized[:metadata] = parsed_metadata if values.key?(:metadata)

      requirement = new
      requirement.replace(normalized)
      requirement
    end

    sig { returns(T.nilable(String)) }
    def requirement
      value = self[:requirement]
      value.is_a?(String) ? value : nil
    end

    sig { returns(T::Boolean) }
    def unfixable?
      self[:requirement] == :unfixable
    end

    sig { returns(T.nilable(String)) }
    def file
      value = self[:file]
      value.is_a?(String) ? value : nil
    end

    sig { returns(T.nilable(T::Array[Group])) }
    def groups
      value = self[:groups]
      T.cast(value, T.nilable(T::Array[Group]))
    end

    sig { returns(T.nilable(Details)) }
    def source
      T.cast(self[:source], T.nilable(Details))
    end

    sig { returns(T.nilable(Details)) }
    def metadata
      T.cast(self[:metadata], T.nilable(Details))
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
      each_with_object(T.let({}, T::Hash[Symbol, Object])) do |(key, value), hash|
        hash[key] = value
      end
    end

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

      sig { params(value: Object).returns(T.nilable(T.any(String, Symbol))) }
      def parse_requirement(value)
        return if value.nil?
        return value if value.is_a?(String) && !value.empty?
        return :unfixable if value == :unfixable
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
        unless value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) || entry.is_a?(Symbol) }
          raise TypeError, "groups must be an array of strings or symbols, or nil"
        end

        value.map { |entry| T.cast(entry, Group) }.freeze
      end

      sig { params(value: T.nilable(Object), name: String).returns(T.nilable(Details)) }
      def parse_details(value, name)
        return if value.nil?
        raise TypeError, "#{name} must be a hash or nil" unless value.is_a?(Hash)

        value.each_with_object(T.let({}, Details)) do |(raw_key, raw_value), result|
          key = T.cast(raw_key, Object)
          raise TypeError, "#{name} keys must be strings or symbols" unless key.is_a?(String) || key.is_a?(Symbol)

          result[key] = T.cast(raw_value, Object)
        end.freeze
      end
    end
  end
end
