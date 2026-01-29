# typed: strict
# frozen_string_literal: true

require "dependabot/pull_request_creator/message_components/base"
require "dependabot/pull_request_creator/pr_name_prefixer"

module Dependabot
  class PullRequestCreator
    module MessageComponents
      # Base class for PR title generation
      # Handles prefix and capitalization logic consistently
      class PrTitle < Base
        extend T::Sig
        extend T::Helpers

        abstract!

        sig { override.returns(String) }
        def build
          title = base_title
          title[0] = T.must(title[0]).capitalize if pr_name_prefixer.capitalize_first_word?
          "#{pr_name_prefix}#{title}"
        end

        sig { abstract.returns(String) }
        def base_title; end

        private

        sig { returns(String) }
        def pr_name_prefix
          pr_name_prefixer.pr_name_prefix
        rescue StandardError
          ""
        end

        sig { returns(Dependabot::PullRequestCreator::PrNamePrefixer) }
        def pr_name_prefixer
          @pr_name_prefixer ||= T.let(
            Dependabot::PullRequestCreator::PrNamePrefixer.new(
              source: source,
              dependencies: dependencies,
              credentials: credentials,
              commit_message_options: commit_message_options || {},
              security_fix: security_fix?
            ),
            T.nilable(Dependabot::PullRequestCreator::PrNamePrefixer)
          )
        end

        sig { returns(T::Boolean) }
        def security_fix?
          vulnerabilities_fixed.values.flatten.any?
        end

        sig { returns(String) }
        def pr_name_directory
          return "" if files.empty?
          return "" if T.must(files.first).directory == "/"

          " in #{T.must(files.first).directory}"
        end
      end
    end
  end
end
