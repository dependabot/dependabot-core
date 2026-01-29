# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      module Strategies
        # Base class for title generation strategies.
        # Each strategy knows how to generate the "base title" (without prefix)
        # for a specific type of update.
        class Base
          extend T::Sig
          extend T::Helpers

          abstract!

          # Returns the base title without any prefix
          sig { abstract.returns(String) }
          def base_title; end

          # Returns the base commit subject without any prefix
          sig { returns(String) }
          def commit_subject
            base_title
          end
        end
      end
    end
  end
end