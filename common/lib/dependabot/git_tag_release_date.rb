# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class GitTagReleaseDate
    extend T::Sig

    sig { returns(String) }
    attr_accessor :tag

    sig { returns(String) }
    attr_accessor :release_date

    sig do
      params(
        tag: String,
        release_date: String
      ).void
    end
    def initialize(tag:, release_date:)
      @tag = tag
      @release_date = release_date
    end

    sig { params(other: BasicObject).returns(T::Boolean) }
    def ==(other)
      case other
      when GitTagReleaseDate
        to_h == other.to_h
      else
        false
      end
    end

    sig { returns(T::Hash[Symbol, T.nilable(String)]) }
    def to_h
      {
        tag: tag,
        release_date: release_date
      }.compact
    end
  end
end
