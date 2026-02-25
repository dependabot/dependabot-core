# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      module Strategies
        class Base
          extend T::Sig
          extend T::Helpers

          abstract!

          sig { abstract.returns(String) }
          def base_title; end
        end
      end
    end
  end
end
