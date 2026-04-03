# typed: strong
# frozen_string_literal: true

# Signatures for dynamic attributes accessed on Sawyer::Resource via method_missing,
# and for Sawyer::Response fields used in Octokit pagination.

class Sawyer::Response
  sig { returns(T::Hash[Symbol, Sawyer::Relation]) }
  def rels; end

  sig { returns(T.untyped) }
  def data; end
end

class Sawyer::Relation
  sig { returns(Sawyer::Response) }
  def get; end

  sig { returns(String) }
  def href; end
end
