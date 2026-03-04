# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/logger"
require "dependabot/pull_request_creator/pr_name_prefixer"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      # Composes a final PR title from a base title + prefix.
      #
      # Works in two modes:
      # 1. With a full PrNamePrefixer (updater path — has source/credentials for
      #    commit style auto-detection)
      # 2. With just commit_message_options (API path — explicit prefix only,
      #    no network calls needed)
      class TitleBuilder
        extend T::Sig

        sig { returns(String) }
        attr_reader :base_title

        sig { returns(T.nilable(Dependabot::PullRequestCreator::PrNamePrefixer)) }
        attr_reader :prefixer

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        attr_reader :commit_message_options

        sig { returns(T.nilable(T::Array[Dependabot::Dependency])) }
        attr_reader :dependencies

        sig do
          params(
            base_title: String,
            prefixer: T.nilable(Dependabot::PullRequestCreator::PrNamePrefixer),
            commit_message_options: T.nilable(T::Hash[Symbol, T.untyped]),
            dependencies: T.nilable(T::Array[Dependabot::Dependency])
          ).void
        end
        def initialize(base_title:, prefixer: nil, commit_message_options: nil, dependencies: nil)
          @base_title = base_title
          @prefixer = prefixer
          @commit_message_options = commit_message_options
          @dependencies = dependencies
        end

        # Generates a base title for multi-ecosystem combined PR updates.
        sig { params(group_name: String, update_count: Integer).returns(String) }
        def self.multi_ecosystem_base_title(group_name:, update_count:)
          "bump the \"#{group_name}\" group with " \
            "#{update_count} update#{'s' if update_count > 1} across multiple ecosystems"
        end

        sig { returns(String) }
        def build
          name = base_title.dup
          name[0] = T.must(name[0]).capitalize if capitalize?
          "#{prefix}#{name}"
        end

        private

        sig { returns(String) }
        def prefix
          return T.must(prefixer).pr_name_prefix if prefixer

          build_explicit_prefix
        rescue StandardError => e
          Dependabot.logger.error("Error while generating PR name prefix: #{e.message}")
          Dependabot.logger.error(e.backtrace&.join("\n"))
          ""
        end

        sig { returns(T::Boolean) }
        def capitalize?
          return T.must(prefixer).capitalize_first_word? if prefixer

          false
        end

        # Builds prefix from explicit commit_message_options only.
        # Same logic as PrNamePrefixer#prefix_from_explicitly_provided_details
        # but without requiring source/credentials.
        sig { returns(String) }
        def build_explicit_prefix
          return "" unless commit_message_options&.key?(:prefix)

          prefix = explicit_prefix_string
          return "" if prefix.empty?

          prefix += "(#{scope})" if commit_message_options&.dig(:include_scope)
          # Append colon after alphanumeric or closing bracket to follow
          # conventional commit format (e.g., "chore: ..." or "fix(deps): ...")
          prefix += ":" if prefix.match?(/[A-Za-z0-9\)\]]\Z/)
          prefix += " " unless prefix.end_with?(" ")
          prefix
        end

        sig { returns(String) }
        def explicit_prefix_string
          if production_dependencies?
            commit_message_options&.dig(:prefix).to_s
          elsif commit_message_options&.key?(:prefix_development)
            commit_message_options&.dig(:prefix_development).to_s
          else
            commit_message_options&.dig(:prefix).to_s
          end
        end

        sig { returns(T::Boolean) }
        def production_dependencies?
          dependencies&.any?(&:production?) != false
        rescue StandardError
          true
        end

        sig { returns(String) }
        def scope
          production_dependencies? ? "deps" : "deps-dev"
        end
      end
    end
  end
end
