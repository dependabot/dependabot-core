# typed: strong
# frozen_string_literal: true

# Signatures for Sawyer::Response fields used in Octokit pagination.

class Sawyer::Response
  sig { returns(T::Hash[Symbol, Sawyer::Relation]) }
  def rels; end

  sig { returns(T.untyped) }
  def data; end
end
