# typed: strong
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
  # Subclasses Hash so it is a drop-in replacement at call sites (and in
  # type annotations) that treat requirement entries as
  # T::Hash[Symbol, T.untyped], while exposing typed readers for the
  # well-known keys. New code should prefer the typed readers; hash-style
  # access remains supported while call sites are migrated gradually.
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

    Group = T.type_alias { T.any(String, Symbol) }
    ObjectHash = T.type_alias { T::Hash[T.any(Symbol, String), Object] }
    Requirement = T.type_alias { T.any(String, Symbol) }
    Input = T.type_alias { T.any(DependencyRequirement, ObjectHash) }

    K = type_member { { fixed: Symbol } }
    # Hash-style access remains dynamic until ecosystem callers migrate to the
    # typed readers. Keeping that compatibility here avoids a flag-day change.
    # rubocop:disable Sorbet/ForbidTUntyped
    V = type_member { { fixed: T.untyped } }
    Elem = type_member { { fixed: [Symbol, T.untyped] } }
    # rubocop:enable Sorbet/ForbidTUntyped

    # Builds a DependencyRequirement from a requirement hash, symbolising
    # top-level keys. Accepts both plain hashes and existing
    # DependencyRequirement instances and always returns a new instance.
    sig { params(hash: Input).returns(DependencyRequirement) }
    def self.create(hash)
      requirement = new
      requirement.replace(hash.keys.to_h { |k| [k.to_sym, hash[k]] })
      requirement
    end

    # The version constraint string, e.g. ">= 1.0, < 2.0". Nil when the
    # dependency is pinned by a lockfile rather than a manifest constraint.
    sig { returns(T.nilable(Requirement)) }
    def requirement
      value = T.cast(self[:requirement], T.nilable(Object))
      return if value.nil?
      return value if value.is_a?(String) || value == :unfixable

      raise TypeError, "requirement must be a string, :unfixable, or nil"
    end

    # The manifest file this requirement was declared in, e.g. "Gemfile".
    sig { returns(T.nilable(String)) }
    def file
      optional_string(:file)
    end

    # The dependency groups this requirement belongs to, e.g. ["dev"] or
    # [:default]. Element types vary by ecosystem (strings or symbols).
    # Nilable because some requirement entries are constructed with
    # groups: nil, and the reader must reflect that to stay a drop-in for
    # the underlying hash access under sorbet-runtime.
    sig { returns(T.nilable(T::Array[Group])) }
    def groups
      value = T.cast(self[:groups], T.nilable(Object))
      return if value.nil?
      raise TypeError, "groups must be an array of strings or symbols, or nil" unless value.is_a?(Array)

      value.each do |raw_group|
        group = T.cast(raw_group, Object)
        next if group.is_a?(String) || group.is_a?(Symbol)

        raise TypeError, "groups must be an array of strings or symbols, or nil"
      end
      value
    end

    # The source details for the dependency, e.g.
    # { type: "git", url: "https://github.com/..." }. Keys may be symbols
    # or strings depending on whether the requirement was built by a file
    # parser or deserialised from a job definition.
    sig { returns(T.nilable(ObjectHash)) }
    def source
      optional_object_hash(:source)
    end

    # Optional ecosystem-specific metadata about the requirement, e.g.
    # { property_name: "rails.version" }.
    sig { returns(T.nilable(ObjectHash)) }
    def metadata
      optional_object_hash(:metadata)
    end

    private

    sig { params(key: Symbol).returns(T.nilable(String)) }
    def optional_string(key)
      value = T.cast(self[key], T.nilable(Object))
      return if value.nil?
      return value if value.is_a?(String)

      raise TypeError, "#{key} must be a string or nil"
    end

    sig { params(key: Symbol).returns(T.nilable(ObjectHash)) }
    def optional_object_hash(key)
      value = T.cast(self[key], T.nilable(Object))
      return if value.nil?
      raise TypeError, "#{key} must be a hash with string or symbol keys, or nil" unless value.is_a?(Hash)

      value.each_key do |raw_nested_key|
        nested_key = T.cast(raw_nested_key, Object)
        next if nested_key.is_a?(String) || nested_key.is_a?(Symbol)

        raise TypeError, "#{key} must be a hash with string or symbol keys, or nil"
      end
      value
    end
  end
end
