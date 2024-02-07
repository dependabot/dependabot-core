# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class GitRef
    extend T::Sig

    sig { returns(String) }
    attr_accessor :name

    sig { returns(String) }
    attr_accessor :commit_sha

    sig { returns(T.nilable(String)) }
    attr_reader :tag_sha

    sig { returns(T.nilable(String)) }
    attr_reader :ref_sha

    sig { returns(T.nilable(RefType)) }
    attr_reader :ref_type

    sig do
      params(
        name: String,
        commit_sha: String,
        tag_sha: T.nilable(String),
        ref_sha: T.nilable(String),
        ref_type: T.nilable(RefType)
      )
        .void
    end
    def initialize(name:, commit_sha:, tag_sha: nil, ref_sha: nil, ref_type: nil)
      @name = name
      @commit_sha = commit_sha
      @ref_sha = ref_sha
      @tag_sha = tag_sha
      @ref_type = ref_type
    end

    sig { params(other: BasicObject).returns(T::Boolean) }
    def ==(other)
      case other
      when GitRef
        to_h == other.to_h
      else
        false
      end
    end

    sig { returns(T::Hash[Symbol, T.nilable(String)]) }
    def to_h
      {
        name: name,
        commit_sha: commit_sha,
        tag_sha: tag_sha,
        ref_sha: ref_sha,
        ref_type: ref_type
      }.compact
    end
  end

  class RefType < T::Enum
    enums do
      Tag = new
      Head = new
    end
  end
end
