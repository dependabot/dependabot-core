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
  # T::Hash[Symbol, Object], while exposing typed readers for the
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

    DEPENDENCY_SUBSTITUTION_DECLARATION_TYPE = "dependency_substitution"

    Group = T.type_alias { T.any(String, Symbol) }
    ObjectHash = T.type_alias { T::Hash[T.any(Symbol, String), Object] }
    Requirement = T.type_alias { T.any(String, Symbol) }
    Source = T.type_alias { T.any(String, ObjectHash) }
    Input = T.type_alias { T::Hash[T.any(Symbol, String), T.anything] }

    K = type_member { { fixed: Symbol } }
    V = type_member { { fixed: Object } }
    Elem = type_member { { fixed: [Symbol, Object] } }

    # Builds a DependencyRequirement from a requirement hash, symbolising
    # top-level keys. Accepts both plain hashes and existing
    # DependencyRequirement instances and always returns a new instance.
    sig { params(hash: Input).returns(DependencyRequirement) }
    def self.create(hash)
      requirement = new
      hash.each do |key, value|
        case value
        when Object then requirement[key.to_sym] = value
        else raise TypeError, "requirement values must inherit Object"
        end
      end
      requirement
    end

    # The version constraint string, e.g. ">= 1.0, < 2.0". Nil when the
    # dependency is pinned by a lockfile rather than a manifest constraint,
    # or :unfixable when no valid updated requirement can be generated.
    sig { returns(T.nilable(Requirement)) }
    def requirement
      value = self[:requirement]
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
      value = self[:groups]
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
    sig { returns(T.nilable(Source)) }
    def source
      value = self[:source]
      return if value.nil?
      return value if value.is_a?(String)

      object_hash(value, :source)
    end

    # Optional ecosystem-specific metadata about the requirement, e.g.
    # { property_name: "rails.version" }.
    sig { returns(T.nilable(ObjectHash)) }
    def metadata
      optional_object_hash(:metadata)
    end

    # The source as a hash, or nil when the requirement has no source or
    # names a registry as a bare string (e.g. Python's "internal" index).
    sig { returns(T.nilable(ObjectHash)) }
    def source_hash
      value = source
      return if value.nil? || value.is_a?(String)

      value
    end

    # Reads a known source field such as "type", "ref", "url", or "digest".
    # Accepts either key style because file parsers emit symbols while
    # deserialised job definitions emit strings. Returns nil when the source
    # is absent or a bare registry name.
    sig { params(key: String).returns(T.nilable(String)) }
    def source_string(key)
      details = source_hash
      return if details.nil?

      value = details[key.to_sym] || details[key]
      return if value.nil?
      return value if value.is_a?(String)

      raise TypeError, "source #{key} must be a string or nil"
    end

    # The requirement as a plain string. Nil when the requirement is absent,
    # and a TypeError for the `:unfixable` sentinel, which callers that build
    # manifest content cannot render.
    sig { returns(T.nilable(String)) }
    def requirement_string
      value = requirement
      return if value.nil?
      return value if value.is_a?(String)

      raise TypeError, "requirement must be a string or nil"
    end

    # Reads a known metadata field such as "property_name". Accepts either key
    # style for the same reason as `source_string`. Returns nil when the
    # requirement carries no metadata or the key is absent.
    sig { params(key: String).returns(T.nilable(String)) }
    def metadata_string(key)
      value = metadata_value(key)
      return if value.nil?
      return value if value.is_a?(String)

      raise TypeError, "metadata #{key} must be a string or nil"
    end

    # Reads a known symbol-valued metadata field such as Helm's "type".
    sig { params(key: String).returns(T.nilable(Symbol)) }
    def metadata_symbol(key)
      value = metadata_value(key)
      return if value.nil?
      return value if value.is_a?(Symbol)

      raise TypeError, "metadata #{key} must be a symbol or nil"
    end

    # Reads a boolean metadata field such as "include_debug_script".
    sig { params(key: String).returns(T.nilable(T::Boolean)) }
    def metadata_boolean(key)
      value = metadata_value(key)
      return if value.nil?
      return value if value == true || value == false

      raise TypeError, "metadata #{key} must be a boolean or nil"
    end

    # Reads a nested metadata hash whose values are all strings, such as
    # "dependency_set" (`{ group: "my.group", version: "1.4.0" }`). Keys are
    # symbolised so callers can read them with symbols regardless of how the
    # requirement was built.
    sig { params(key: String).returns(T.nilable(T::Hash[Symbol, String])) }
    def metadata_string_hash(key)
      value = metadata_value(key)
      return if value.nil?
      raise TypeError, "metadata #{key} must be a hash of strings or nil" unless value.is_a?(Hash)

      value.to_h do |raw_entry_key, raw_entry_value|
        entry_key = T.cast(raw_entry_key, Object)
        entry_value = T.cast(raw_entry_value, Object)
        unless (entry_key.is_a?(Symbol) || entry_key.is_a?(String)) && entry_value.is_a?(String)
          raise TypeError, "metadata #{key} must be a hash of strings or nil"
        end

        [entry_key.to_sym, entry_value]
      end
    end

    private

    # Reads a raw metadata field, accepting either key style. Nil when the
    # requirement carries no metadata or the key is absent.
    sig { params(key: String).returns(T.nilable(Object)) }
    def metadata_value(key)
      details = metadata
      return if details.nil?

      return details[key.to_sym] if details.key?(key.to_sym)

      details[key]
    end

    sig { params(key: Symbol).returns(T.nilable(String)) }
    def optional_string(key)
      value = self[key]
      return if value.nil?
      return value if value.is_a?(String)

      raise TypeError, "#{key} must be a string or nil"
    end

    sig { params(key: Symbol).returns(T.nilable(ObjectHash)) }
    def optional_object_hash(key)
      value = self[key]
      return if value.nil?

      object_hash(value, key)
    end

    sig { params(value: Object, key: Symbol).returns(ObjectHash) }
    def object_hash(value, key)
      message = object_hash_message(key)
      raise TypeError, "#{key} must be #{message}" unless value.is_a?(Hash)

      value.each_key do |raw_nested_key|
        nested_key = T.cast(raw_nested_key, Object)
        next if nested_key.is_a?(String) || nested_key.is_a?(Symbol)

        raise TypeError, "#{key} must be #{message}"
      end
      value
    end

    sig { params(key: Symbol).returns(String) }
    def object_hash_message(key)
      return "a string or hash with string or symbol keys, or nil" if key == :source

      "a hash with string or symbol keys, or nil"
    end
  end
end
