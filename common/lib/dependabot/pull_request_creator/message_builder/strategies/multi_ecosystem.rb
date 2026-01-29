# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "base"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      module Strategies
        # Generates base title for multi-ecosystem grouped updates.
        # Used by both dependabot-core and dependabot-api.
        class MultiEcosystem < Base
          sig do
            params(
              group_name: String,
              update_count: Integer
            ).void
          end
          def initialize(group_name:, update_count:)
            @group_name = group_name
            @update_count = update_count
          end

          sig { override.returns(String) }
          def base_title
            "bump the \"#{@group_name}\" group with #{@update_count} updates across multiple ecosystems"
          end
        end
      end
    end
  end
end