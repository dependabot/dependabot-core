# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Clients
    class ComparisonCommit < T::ImmutableStruct
      extend T::Sig

      const :sha, String
      const :message, String
      const :html_url, String

      sig { returns(T::Hash[Symbol, String]) }
      def to_h
        { message: message, sha: sha, html_url: html_url }
      end
    end
  end
end
