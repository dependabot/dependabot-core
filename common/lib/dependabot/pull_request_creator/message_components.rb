# typed: strict
# frozen_string_literal: true

require "dependabot/pull_request_creator/message_components/single_update_title"
require "dependabot/pull_request_creator/message_components/group_update_title"
require "dependabot/pull_request_creator/message_components/multi_ecosystem_title"

module Dependabot
  class PullRequestCreator
    module MessageComponents
      # Factory for creating appropriate message title components
      # This provides a discoverable API for both dependabot-core and dependabot-api
      #
      # Usage:
      #   # In dependabot-core (single update)
      #   title = MessageComponents.create_title(
      #     type: :single,
      #     dependencies: [dependency],
      #     source: source,
      #     credentials: credentials,
      #     files: files
      #   )
      #
      #   # In dependabot-api (multi-ecosystem)
      #   title = Dependabot::PullRequestCreator::MessageComponents.create_title(
      #     type: :multi_ecosystem,
      #     dependencies: all_dependencies,
      #     source: source,
      #     credentials: credentials,
      #     dependency_group: group
      #   )
      class << self
        extend T::Sig

        sig do
          params(
            type: Symbol,
            dependencies: T::Array[Dependabot::Dependency],
            source: Dependabot::Source,
            credentials: T::Array[Dependabot::Credential],
            files: T::Array[Dependabot::DependencyFile],
            vulnerabilities_fixed: T::Hash[String, T.untyped],
            commit_message_options: T.nilable(T::Hash[Symbol, T.untyped]),
            dependency_group: T.nilable(Dependabot::DependencyGroup)
          )
            .returns(PrTitle)
        end
        def create_title(
          type:,
          dependencies:,
          source:,
          credentials:,
          files: [],
          vulnerabilities_fixed: {},
          commit_message_options: nil,
          dependency_group: nil
        )
          component_class = case type
                            when :single
                              SingleUpdateTitle
                            when :group
                              GroupUpdateTitle
                            when :multi_ecosystem
                              MultiEcosystemTitle
                            else
                              raise ArgumentError, "Unknown title type: #{type}. " \
                                                   "Valid types: :single, :group, :multi_ecosystem"
                            end

          component_class.new(
            dependencies: dependencies,
            source: source,
            credentials: credentials,
            files: files,
            vulnerabilities_fixed: vulnerabilities_fixed,
            commit_message_options: commit_message_options,
            dependency_group: dependency_group
          )
        end
      end
    end
  end
end
