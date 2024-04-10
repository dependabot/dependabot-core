# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Requirement < Gem::Requirement
    extend T::Sig
    extend T::Helpers

    abstract!

    sig do
      abstract
        .params(requirement_string: T.nilable(String))
        .returns(T::Array[Requirement])
    end
    def self.requirements_array(requirement_string); end
  end
end
