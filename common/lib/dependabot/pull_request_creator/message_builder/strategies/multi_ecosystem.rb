# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pull_request_creator/message_builder/strategies/base"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      module Strategies
        class MultiEcosystem < Base
          extend T::Sig

          sig { returns(String) }
          attr_reader :group_name

          sig { returns(Integer) }
          attr_reader :update_count

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
            "bump the \"#{group_name}\" group with " \
              "#{update_count} update#{'s' if update_count > 1} across multiple ecosystems"
          end
        end
      end
    end
  end
end
