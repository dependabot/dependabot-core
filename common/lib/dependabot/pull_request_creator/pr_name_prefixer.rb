# frozen_string_literal: true

require "dependabot/clients/azure"
require "dependabot/clients/bitbucket"
require "dependabot/clients/codecommit"
require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/pull_request_creator"
module Dependabot
  class PullRequestCreator
    class PrNamePrefixer
      ANGULAR_PREFIXES = %w(build chore ci docs feat fix perf refactor style
                            test).freeze
      ESLINT_PREFIXES  = %w(Breaking Build Chore Docs Fix New Update
                            Upgrade).freeze
      GITMOJI_PREFIXES = %w(alien ambulance apple arrow_down arrow_up art beers
                            bento bookmark boom bug building_construction bulb
                            busts_in_silhouette camera_flash card_file_box
                            chart_with_upwards_trend checkered_flag
                            children_crossing clown_face construction
                            construction_worker egg fire globe_with_meridians
                            green_apple green_heart hankey heavy_minus_sign
                            heavy_plus_sign iphone lipstick lock loud_sound memo
                            mute ok_hand package page_facing_up pencil2 penguin
                            pushpin recycle rewind robot rocket rotating_light
                            see_no_evil sparkles speech_balloon tada truck
                            twisted_rightwards_arrows whale wheelchair
                            white_check_mark wrench zap).freeze

      def initialize(source:, dependencies:, credentials:, security_fix: false,
                     commit_message_options: {})
        @dependencies           = dependencies
        @source                 = source
        @credentials            = credentials
        @security_fix           = security_fix
        @commit_message_options = commit_message_options
      end

      def pr_name_prefix
        prefix = commit_prefix.to_s
        prefix += security_prefix if security_fix?
        prefix.gsub("⬆️ 🔒", "⬆️🔒")
      end

      def capitalize_first_word?
        return capitalise_first_word_from_last_dependabot_commit_style if last_dependabot_commit_style

        capitalise_first_word_from_previous_commits
      end

      private

      attr_reader :source, :dependencies, :credentials, :commit_message_options

      def security_fix?
        @security_fix
      end

      def commit_prefix
        # If a preferred prefix has been explicitly provided, use it
        return prefix_from_explicitly_provided_details if commit_message_options.key?(:prefix)

        # Otherwise, if there is a previous Dependabot commit and it used a
        # known style, use that as our model for subsequent commits
        return prefix_for_last_dependabot_commit_style if last_dependabot_commit_style

        # Otherwise we need to detect the user's preferred style from the
        # existing commits on their repo
        build_commit_prefix_from_previous_commits
      end

      def prefix_from_explicitly_provided_details
        prefix = explicitly_provided_prefix_string
        return if prefix.empty?

        prefix += "(#{scope})" if commit_message_options[:include_scope]
        prefix += ":" if prefix.match?(/[A-Za-z0-9\)\]]\Z/)
        prefix += " " unless prefix.end_with?(" ")
        prefix
      end

      def explicitly_provided_prefix_string
        raise "No explicitly provided prefix!" unless commit_message_options.key?(:prefix)

        if dependencies.any?(&:production?)
          commit_message_options[:prefix].to_s
        elsif commit_message_options.key?(:prefix_development)
          commit_message_options[:prefix_development].to_s
        else
          commit_message_options[:prefix].to_s
        end
      end

      def prefix_for_last_dependabot_commit_style
        case last_dependabot_commit_style
        when :gitmoji then "⬆️ "
        when :conventional_prefix then "#{last_dependabot_commit_prefix}: "
        when :conventional_prefix_with_scope
          "#{last_dependabot_commit_prefix}(#{scope}): "
        else raise "Unknown commit style #{last_dependabot_commit_style}"
        end
      end

      def security_prefix
        return "🔒 " if commit_prefix == "⬆️ "

        capitalize_first_word? ? "[Security] " : "[security] "
      end

      def build_commit_prefix_from_previous_commits
        if using_angular_commit_messages?
          "#{angular_commit_prefix}(#{scope}): "
        elsif using_eslint_commit_messages?
          # https://eslint.org/docs/developer-guide/contributing/pull-requests
          "Upgrade: "
        elsif using_gitmoji_commit_messages?
          "⬆️ "
        elsif using_prefixed_commit_messages?
          "build(#{scope}): "
        end
      end

      def scope
        dependencies.any?(&:production?) ? "deps" : "deps-dev"
      end

      def capitalise_first_word_from_last_dependabot_commit_style
        case last_dependabot_commit_style
        when :gitmoji then true
        when :conventional_prefix, :conventional_prefix_with_scope
          last_dependabot_commit_message.match?(/: (\[[Ss]ecurity\] )?(B|U)/)
        else raise "Unknown commit style #{last_dependabot_commit_style}"
        end
      end

      def capitalise_first_word_from_previous_commits
        if using_angular_commit_messages? || using_eslint_commit_messages?
          prefixes = ANGULAR_PREFIXES + ESLINT_PREFIXES
          semantic_msgs = recent_commit_messages.select do |message|
            prefixes.any? { |pre| message.match?(/#{pre}[:(]/i) }
          end

          return true if semantic_msgs.all? { |m| m.match?(/:\s+\[?[A-Z]/) }
          return false if semantic_msgs.all? { |m| m.match?(/:\s+\[?[a-z]/) }
        end

        !commit_prefix&.match(/\A[a-z]/)
      end

      def last_dependabot_commit_style
        return unless (msg = last_dependabot_commit_message)

        return :gitmoji if msg.start_with?("⬆️")
        return :conventional_prefix if msg.match?(/\A(chore|build|upgrade):/i)
        return unless msg.match?(/\A(chore|build|upgrade)\(/i)

        :conventional_prefix_with_scope
      end

      def last_dependabot_commit_prefix
        last_dependabot_commit_message&.split(/[:(]/)&.first
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def using_angular_commit_messages?
        return false if recent_commit_messages.none?

        angular_messages = recent_commit_messages.select do |message|
          ANGULAR_PREFIXES.any? { |pre| message.match?(/#{pre}[:(]/i) }
        end

        # Definitely not using Angular commits if < 30% match angular commits
        return false if angular_messages.count.to_f / recent_commit_messages.count < 0.3

        eslint_only_pres = ESLINT_PREFIXES.map(&:downcase) - ANGULAR_PREFIXES
        angular_only_pres = ANGULAR_PREFIXES - ESLINT_PREFIXES.map(&:downcase)

        uses_eslint_only_pres =
          recent_commit_messages.
          any? { |m| eslint_only_pres.any? { |pre| m.match?(/#{pre}[:(]/i) } }

        uses_angular_only_pres =
          recent_commit_messages.
          any? { |m| angular_only_pres.any? { |pre| m.match?(/#{pre}[:(]/i) } }

        # If using any angular-only prefixes, return true
        # (i.e., we assume Angular over ESLint when both are present)
        return true if uses_angular_only_pres
        return false if uses_eslint_only_pres

        true
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def using_eslint_commit_messages?
        return false if recent_commit_messages.none?

        semantic_messages = recent_commit_messages.select do |message|
          ESLINT_PREFIXES.any? { |pre| message.start_with?(/#{pre}[:(]/) }
        end

        semantic_messages.count.to_f / recent_commit_messages.count > 0.3
      end

      def using_prefixed_commit_messages?
        return false if using_gitmoji_commit_messages?
        return false if recent_commit_messages.none?

        prefixed_messages = recent_commit_messages.select do |message|
          message.start_with?(/[a-z][^\s]+:/)
        end

        prefixed_messages.count.to_f / recent_commit_messages.count > 0.3
      end

      def angular_commit_prefix
        raise "Not using angular commits!" unless using_angular_commit_messages?

        recent_commits_using_chore =
          recent_commit_messages.
          any? { |msg| msg.start_with?("chore", "Chore") }

        recent_commits_using_build =
          recent_commit_messages.
          any? { |msg| msg.start_with?("build", "Build") }

        commit_prefix =
          if recent_commits_using_chore && !recent_commits_using_build
            "chore"
          else
            "build"
          end

        commit_prefix = commit_prefix.capitalize if capitalize_angular_commit_prefix?

        commit_prefix
      end

      def capitalize_angular_commit_prefix?
        semantic_messages = recent_commit_messages.select do |message|
          ANGULAR_PREFIXES.any? { |pre| message.match?(/#{pre}[:(]/i) }
        end

        return last_dependabot_commit_message&.start_with?(/[A-Z]/) if semantic_messages.none?

        capitalized_msgs = semantic_messages.
                           select { |m| m.start_with?(/[A-Z]/) }
        capitalized_msgs.count.to_f / semantic_messages.count > 0.5
      end

      def using_gitmoji_commit_messages?
        return false unless recent_commit_messages.any?

        gitmoji_messages =
          recent_commit_messages.
          select { |m| GITMOJI_PREFIXES.any? { |pre| m.match?(/:#{pre}:/i) } }

        gitmoji_messages.count / recent_commit_messages.count.to_f > 0.3
      end

      def recent_commit_messages
        case source.provider
        when "github" then recent_github_commit_messages
        when "gitlab" then recent_gitlab_commit_messages
        when "azure" then recent_azure_commit_messages
        when "bitbucket" then recent_bitbucket_commit_messages
        when "codecommit" then recent_codecommit_commit_messages
        else raise "Unsupported provider: #{source.provider}"
        end
      end

      def dependabot_email
        "support@dependabot.com"
      end

      def recent_github_commit_messages
        recent_github_commits.
          reject { |c| c.author&.type == "Bot" }.
          reject { |c| c.commit&.message&.start_with?("Merge") }.
          map(&:commit).
          filter_map(&:message).
          map(&:strip)
      end

      def recent_gitlab_commit_messages
        @recent_gitlab_commit_messages ||=
          gitlab_client_for_source.commits(source.repo)

        @recent_gitlab_commit_messages.
          reject { |c| c.author_email == dependabot_email }.
          reject { |c| c.message&.start_with?("merge !") }.
          filter_map(&:message).
          map(&:strip)
      end

      def recent_azure_commit_messages
        @recent_azure_commit_messages ||=
          azure_client_for_source.commits

        @recent_azure_commit_messages.
          reject { |c| azure_commit_author_email(c) == dependabot_email }.
          reject { |c| c.fetch("comment")&.start_with?("Merge") }.
          filter_map { |c| c.fetch("comment") }.
          map(&:strip)
      end

      def recent_bitbucket_commit_messages
        @recent_bitbucket_commit_messages ||=
          bitbucket_client_for_source.commits(source.repo)

        @recent_bitbucket_commit_messages.
          reject { |c| bitbucket_commit_author_email(c) == dependabot_email }.
          filter_map { |c| c.fetch("message", nil) }.
          reject { |m| m.start_with?("Merge") }.
          map(&:strip)
      end

      def recent_codecommit_commit_messages
        @recent_codecommit_commit_messages ||=
          codecommit_client_for_source.commits
        @recent_codecommit_commit_messages.commits.
          reject { |c| c.author.email == dependabot_email }.
          reject { |c| c.message&.start_with?("Merge") }.
          filter_map(&:message).
          map(&:strip)
      end

      def last_dependabot_commit_message
        @last_dependabot_commit_message ||=
          case source.provider
          when "github" then last_github_dependabot_commit_message
          when "gitlab" then last_gitlab_dependabot_commit_message
          when "azure" then last_azure_dependabot_commit_message
          when "bitbucket" then last_bitbucket_dependabot_commit_message
          when "codecommit" then last_codecommit_dependabot_commit_message
          else raise "Unsupported provider: #{source.provider}"
          end
      end

      def last_github_dependabot_commit_message
        recent_github_commits.
          reject { |c| c.commit&.message&.start_with?("Merge") }.
          find { |c| c.commit.author&.name&.include?("dependabot") }&.
          commit&.
          message&.
          strip
      end

      def recent_github_commits
        @recent_github_commits ||=
          github_client_for_source.commits(source.repo, per_page: 100)
      rescue Octokit::Conflict, Octokit::NotFound
        @recent_github_commits ||= []
      end

      def last_gitlab_dependabot_commit_message
        @recent_gitlab_commit_messages ||=
          gitlab_client_for_source.commits(source.repo)

        @recent_gitlab_commit_messages.
          find { |c| c.author_email == dependabot_email }&.
          message&.
          strip
      end

      def last_azure_dependabot_commit_message
        @recent_azure_commit_messages ||=
          azure_client_for_source.commits

        @recent_azure_commit_messages.
          find { |c| azure_commit_author_email(c) == dependabot_email }&.
          message&.
          strip
      end

      def last_bitbucket_dependabot_commit_message
        @recent_bitbucket_commit_messages ||=
          bitbucket_client_for_source.commits(source.repo)

        @recent_bitbucket_commit_messages.
          find { |c| bitbucket_commit_author_email(c) == dependabot_email }&.
          fetch("message", nil)&.
          strip
      end

      def last_codecommit_dependabot_commit_message
        @recent_codecommit_commit_messages ||=
          codecommit_client_for_source.commits(source.repo)

        @recent_codecommit_commit_messages.commits.
          find { |c| c.author.email == dependabot_email }&.
          message&.
          strip
      end

      def azure_commit_author_email(commit)
        commit.fetch("author").fetch("email", "")
      end

      def bitbucket_commit_author_email(commit)
        matches = commit.fetch("author").fetch("raw").match(/<(.*)>/)
        matches ? matches[1] : ""
      end

      def github_client_for_source
        @github_client_for_source ||=
          Dependabot::Clients::GithubWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def gitlab_client_for_source
        @gitlab_client_for_source ||=
          Dependabot::Clients::GitlabWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def azure_client_for_source
        @azure_client_for_source ||=
          Dependabot::Clients::Azure.for_source(
            source: source,
            credentials: credentials
          )
      end

      def bitbucket_client_for_source
        @bitbucket_client_for_source ||=
          Dependabot::Clients::Bitbucket.for_source(
            source: source,
            credentials: credentials
          )
      end

      def codecommit_client_for_source
        @codecommit_client_for_source ||=
          Dependabot::Clients::CodeCommit.for_source(
            source: source,
            credentials: credentials
          )
      end

      def package_manager
        @package_manager ||= dependencies.first.package_manager
      end
    end
  end
end
