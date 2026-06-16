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

    # The values of a requirement entry are heterogeneous and
    # ecosystem-specific, so this bridge class is necessarily untyped at
    # the Hash level; the typed readers below are the migration path.
    # rubocop:disable Sorbet/ForbidTUntyped
    K = type_member { { fixed: Symbol } }
    V = type_member { { fixed: T.untyped } }
    Elem = type_member { { fixed: [Symbol, T.untyped] } }

    # Builds a DependencyRequirement from a requirement hash, symbolising
    # top-level keys. Accepts both plain hashes and existing
    # DependencyRequirement instances and always returns a new instance.
    sig { params(hash: T::Hash[T.any(Symbol, String), T.untyped]).returns(DependencyRequirement) }
    def self.create(hash)
      requirement = new
      requirement.replace(hash.keys.to_h { |k| [k.to_sym, hash[k]] })
      requirement
    end

    # The version constraint string, e.g. ">= 1.0, < 2.0". Nil when the
    # dependency is pinned by a lockfile rather than a manifest constraint.
    sig { returns(T.nilable(String)) }
    def requirement
      self[:requirement]
    end

    # The manifest file this requirement was declared in, e.g. "Gemfile".
    sig { returns(T.nilable(String)) }
    def file
      self[:file]
    end

    # The dependency groups this requirement belongs to, e.g. ["dev"] or
    # [:default]. Element types vary by ecosystem (strings or symbols).
    # Nilable because some requirement entries are constructed with
    # groups: nil, and the reader must reflect that to stay a drop-in for
    # the underlying hash access under sorbet-runtime.
    sig { returns(T.nilable(T::Array[T.untyped])) }
    def groups
      self[:groups]
    end

    # The source details for the dependency, e.g.
    # { type: "git", url: "https://github.com/..." }. Keys may be symbols
    # or strings depending on whether the requirement was built by a file
    # parser or deserialised from a job definition.
    sig { returns(T.nilable(T::Hash[T.any(Symbol, String), T.untyped])) }
    def source
      self[:source]
    end

    # Optional ecosystem-specific metadata about the requirement, e.g.
    # { property_name: "rails.version" }.
    sig { returns(T.nilable(T::Hash[T.any(Symbol, String), T.untyped])) }
    def metadata
      self[:metadata]
    end
    # rubocop:enable Sorbet/ForbidTUntyped
  end
end
