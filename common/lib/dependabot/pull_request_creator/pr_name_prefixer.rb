# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/credential"
require "dependabot/clients/azure"
require "dependabot/clients/bitbucket"
require "dependabot/clients/codecommit"
require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/pull_request_creator"
require "dependabot/pull_request_creator/commit_message_options"
require "dependabot/errors"

module Dependabot
  class PullRequestCreator
    class PrNamePrefixer # rubocop:disable Metrics/ClassLength
      extend T::Sig

      ANGULAR_PREFIXES = %w(build chore ci docs feat fix perf refactor style test).freeze
      ESLINT_PREFIXES = %w(Breaking Build Chore Docs Fix New Update Upgrade).freeze
      GITMOJI_PREFIXES = %w(
        alien ambulance apple arrow_down arrow_up art beers bento bookmark boom bug building_construction
        bulb busts_in_silhouette camera_flash card_file_box chart_with_upwards_trend checkered_flag children_crossing
        clown_face construction construction_worker egg fire globe_with_meridians green_apple green_heart hankey
        heavy_minus_sign heavy_plus_sign iphone lipstick lock loud_sound memo mute ok_hand package page_facing_up
        pencil2 penguin pushpin recycle rewind robot rocket rotating_light see_no_evil sparkles speech_balloon tada
        truck twisted_rightwards_arrows whale wheelchair white_check_mark wrench zap
      ).freeze

      class RecentCommit < T::ImmutableStruct
        const :message, T.nilable(String)
        const :author_email, T.nilable(String), default: nil
        const :author_name, T.nilable(String), default: nil
        const :author_type, T.nilable(String), default: nil
      end

      sig do
        params(
          source: Dependabot::Source,
          dependencies: T::Array[Dependency],
          credentials: T::Array[Dependabot::Credential],
          security_fix: T::Boolean,
          commit_message_options: T.nilable(T::Hash[Symbol, T.anything])
        )
          .void
      end
      def initialize(
        source:,
        dependencies:,
        credentials:,
        security_fix: false,
        commit_message_options: {}
      )
        @dependencies           = dependencies
        @source                 = source
        @credentials            = credentials
        @security_fix           = security_fix
        @commit_message_options = T.let(
          commit_message_options && CommitMessageOptions.from_hash(commit_message_options),
          T.nilable(CommitMessageOptions)
        )
        @recent_github_commits = T.let(nil, T.nilable(T::Array[RecentCommit]))
        @recent_gitlab_commits = T.let(nil, T.nilable(T::Array[RecentCommit]))
        @recent_azure_commits = T.let(nil, T.nilable(T::Array[RecentCommit]))
        @recent_bitbucket_commits = T.let(nil, T.nilable(T::Array[RecentCommit]))
        @recent_codecommit_commits = T.let(nil, T.nilable(T::Array[RecentCommit]))
      end

      sig { returns(String) }
      def pr_name_prefix
        prefix = commit_prefix.to_s
        prefix += security_prefix if security_fix?
        prefix.gsub("⬆️ 🔒", "⬆️🔒")
      end

      sig { returns(T::Boolean) }
      def capitalize_first_word?
        return capitalise_first_word_from_last_dependabot_commit_style if last_dependabot_commit_style

        capitalise_first_word_from_previous_commits
      rescue StandardError
        # ignoring failure due to network call to find out if the PR should be capitalized
        false
      end

      private

      sig { returns(Dependabot::Source) }
      attr_reader :source

      sig { returns(T::Array[Dependency]) }
      attr_reader :dependencies

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T.nilable(CommitMessageOptions)) }
      attr_reader :commit_message_options

      sig { returns(T::Boolean) }
      def security_fix?
        @security_fix
      end

      sig { returns(T.nilable(String)) }
      def commit_prefix
        # If a preferred prefix has been explicitly provided, use it
        return prefix_from_explicitly_provided_details if commit_message_options&.prefix?

        # Otherwise, if there is a previous Dependabot commit and it used a
        # known style, use that as our model for subsequent commits
        return prefix_for_last_dependabot_commit_style if last_dependabot_commit_style

        # Otherwise we need to detect the user's preferred style from the
        # existing commits on their repo
        build_commit_prefix_from_previous_commits
      end

      sig { returns(T.nilable(String)) }
      def prefix_from_explicitly_provided_details
        prefix = explicitly_provided_prefix_string
        return if prefix.empty?

        prefix += "(#{scope})" if commit_message_options&.include_scope
        prefix += ":" if prefix.match?(/[A-Za-z0-9\)\]]\Z/)
        prefix += " " unless prefix.end_with?(" ")
        prefix
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { returns(String) }
      def explicitly_provided_prefix_string
        raise "No explicitly provided prefix!" unless commit_message_options&.prefix?

        if dependencies.any?(&:production?)
          commit_message_options&.prefix.to_s
        elsif commit_message_options&.prefix_development?
          commit_message_options&.prefix_development.to_s
        else
          commit_message_options&.prefix.to_s
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { returns(String) }
      def prefix_for_last_dependabot_commit_style
        case last_dependabot_commit_style
        when :gitmoji then "⬆️ "
        when :conventional_prefix then "#{last_dependabot_commit_prefix}: "
        when :conventional_prefix_with_scope
          "#{last_dependabot_commit_prefix}(#{scope}): "
        else raise "Unknown commit style #{last_dependabot_commit_style}"
        end
      end

      sig { returns(String) }
      def security_prefix
        return "🔒 " if commit_prefix == "⬆️ "

        capitalize_first_word? ? "[Security] " : "[security] "
      end

      sig { returns(T.nilable(String)) }
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

      sig { returns(String) }
      def scope
        dependencies.any?(&:production?) ? "deps" : "deps-dev"
      end

      sig { returns(T::Boolean) }
      def capitalise_first_word_from_last_dependabot_commit_style
        case last_dependabot_commit_style
        when :gitmoji then true
        when :conventional_prefix, :conventional_prefix_with_scope
          last_dependabot_commit_title&.match?(/: (\[[Ss]ecurity\] )?(B|U)/) || false
        else raise "Unknown commit style #{last_dependabot_commit_style}"
        end
      end

      sig { returns(T::Boolean) }
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

      sig { returns(T.nilable(Symbol)) }
      def last_dependabot_commit_style
        return unless (msg = last_dependabot_commit_title)

        return :gitmoji if msg.start_with?("⬆️")

        prefixes = (ANGULAR_PREFIXES + ESLINT_PREFIXES).uniq(&:downcase).join("|")
        return :conventional_prefix if msg.match?(/\A(#{prefixes}):/i)
        return :conventional_prefix_with_scope if msg.match?(/\A(#{prefixes})\(/i)

        nil
      end

      sig { returns(T.nilable(String)) }
      def last_dependabot_commit_prefix
        last_dependabot_commit_title&.split(/[:(]/)&.first
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { returns(T::Boolean) }
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
          recent_commit_messages
          .any? { |m| eslint_only_pres.any? { |pre| m.match?(/#{pre}[:(]/i) } }

        uses_angular_only_pres =
          recent_commit_messages
          .any? { |m| angular_only_pres.any? { |pre| m.match?(/#{pre}[:(]/i) } }

        # If using any angular-only prefixes, return true
        # (i.e., we assume Angular over ESLint when both are present)
        return true if uses_angular_only_pres
        return false if uses_eslint_only_pres

        true
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { returns(T::Boolean) }
      def using_eslint_commit_messages?
        return false if recent_commit_messages.none?

        semantic_messages = recent_commit_messages.select do |message|
          ESLINT_PREFIXES.any? { |pre| message.start_with?(/#{pre}[:(]/) }
        end

        semantic_messages.count.to_f / recent_commit_messages.count > 0.3
      end

      sig { returns(T::Boolean) }
      def using_prefixed_commit_messages?
        return false if using_gitmoji_commit_messages?
        return false if recent_commit_messages.none?

        prefixed_messages = recent_commit_messages.select do |message|
          message.start_with?(/[a-z][^\s]+:/)
        end

        prefixed_messages.count.to_f / recent_commit_messages.count > 0.3
      end

      sig { returns(String) }
      def angular_commit_prefix
        raise "Not using angular commits!" unless using_angular_commit_messages?

        recent_commits_using_chore =
          recent_commit_messages
          .any? { |msg| msg.start_with?("chore", "Chore") }

        recent_commits_using_build =
          recent_commit_messages
          .any? { |msg| msg.start_with?("build", "Build") }

        commit_prefix =
          if recent_commits_using_chore && !recent_commits_using_build
            "chore"
          else
            "build"
          end

        commit_prefix = commit_prefix.capitalize if capitalize_angular_commit_prefix?

        commit_prefix
      end

      sig { returns(T::Boolean) }
      def capitalize_angular_commit_prefix?
        semantic_messages = recent_commit_messages.select do |message|
          ANGULAR_PREFIXES.any? { |pre| message.match?(/#{pre}[:(]/i) }
        end

        return last_dependabot_commit_title&.start_with?(/[A-Z]/) || false if semantic_messages.none?

        capitalized_msgs = semantic_messages
                           .select { |m| m.start_with?(/[A-Z]/) }
        capitalized_msgs.count.to_f / semantic_messages.count > 0.5
      end

      sig { returns(T::Boolean) }
      def using_gitmoji_commit_messages?
        return false unless recent_commit_messages.any?

        gitmoji_messages =
          recent_commit_messages
          .select { |m| GITMOJI_PREFIXES.any? { |pre| m.match?(/:#{pre}:/i) } }

        gitmoji_messages.count / recent_commit_messages.count.to_f > 0.3
      end

      sig { returns(T::Array[String]) }
      def recent_commit_messages
        case source.provider
        when "github" then recent_github_commit_messages
        when "gitlab" then recent_gitlab_commit_messages
        when "azure" then recent_azure_commit_messages
        when "bitbucket" then recent_bitbucket_commit_messages
        when "codecommit" then recent_codecommit_commit_messages
        when "example" then []
        else raise "Unsupported provider: #{source.provider}"
        end
      end

      sig { returns(String) }
      def dependabot_email
        "support@dependabot.com"
      end

      sig { returns(T::Array[String]) }
      def recent_github_commit_messages
        recent_github_commits
          .reject { |commit| commit.author_type == "Bot" }
          .reject { |commit| commit.message&.start_with?("Merge") }
          .filter_map(&:message)
          .map(&:strip)
      end

      sig { returns(T::Array[String]) }
      def recent_gitlab_commit_messages
        recent_gitlab_commits
          .reject { |commit| commit.author_email == dependabot_email }
          .reject { |commit| commit.message&.start_with?("merge !") }
          .filter_map(&:message)
          .map(&:strip)
      end

      sig { returns(T::Array[String]) }
      def recent_azure_commit_messages
        recent_azure_commits
          .reject { |commit| commit.author_email == dependabot_email }
          .reject { |commit| commit.message&.start_with?("Merge") }
          .filter_map(&:message)
          .map(&:strip)
      end

      sig { returns(T::Array[String]) }
      def recent_bitbucket_commit_messages
        recent_bitbucket_commits
          .reject { |commit| commit.author_email == dependabot_email }
          .filter_map(&:message)
          .reject { |m| m.start_with?("Merge") }
          .map(&:strip)
      end

      sig { returns(T::Array[String]) }
      def recent_codecommit_commit_messages
        recent_codecommit_commits
          .reject { |commit| commit.author_email == dependabot_email }
          .reject { |commit| commit.message&.start_with?("Merge") }
          .filter_map(&:message)
          .map(&:strip)
      end

      sig { returns(T.nilable(String)) }
      def last_dependabot_commit_title
        @last_dependabot_commit_title ||=
          T.let(
            last_dependabot_commit_message&.split("\n")&.first,
            T.nilable(String)
          )
      end

      sig { returns(T.nilable(String)) }
      def last_dependabot_commit_message
        @last_dependabot_commit_message ||=
          T.let(
            case source.provider
            when "github" then last_github_dependabot_commit_message
            when "gitlab" then last_gitlab_dependabot_commit_message
            when "azure" then last_azure_dependabot_commit_message
            when "bitbucket" then last_bitbucket_dependabot_commit_message
            when "codecommit" then last_codecommit_dependabot_commit_message
            when "example" then nil
            else raise "Unsupported provider: #{source.provider}"
            end,
            T.nilable(String)
          )
      end

      sig { returns(T.nilable(String)) }
      def last_github_dependabot_commit_message
        recent_github_commits
          .reject { |commit| commit.message&.start_with?("Merge") }
          .find { |commit| commit.author_name&.include?("dependabot") }
          &.message
          &.strip
      end

      sig { returns(T::Array[RecentCommit]) }
      def recent_github_commits
        @recent_github_commits ||=
          github_client_for_source
          .commits(source.repo, per_page: 100)
          .map { |commit| parse_github_commit(commit) }
      rescue Octokit::Conflict, Octokit::NotFound
        @recent_github_commits ||= []
      end

      sig { returns(T.nilable(String)) }
      def last_gitlab_dependabot_commit_message
        recent_gitlab_commits
          .find { |commit| commit.author_email == dependabot_email }
          &.message
          &.strip
      end

      sig { returns(T.nilable(String)) }
      def last_azure_dependabot_commit_message
        recent_azure_commits
          .find { |commit| commit.author_email == dependabot_email }
          &.message
          &.strip
      end

      sig { returns(T.nilable(String)) }
      def last_bitbucket_dependabot_commit_message
        recent_bitbucket_commits
          .find { |commit| commit.author_email == dependabot_email }
          &.message
          &.strip
      end

      sig { returns(T.nilable(String)) }
      def last_codecommit_dependabot_commit_message
        recent_codecommit_commits
          .find { |commit| commit.author_email == dependabot_email }
          &.message
          &.strip
      end

      sig { returns(T::Array[RecentCommit]) }
      def recent_gitlab_commits
        @recent_gitlab_commits ||= gitlab_client_for_source
                                   .commits(source.repo)
                                   .map { |commit| parse_gitlab_commit(commit) }
      end

      sig { returns(T::Array[RecentCommit]) }
      def recent_azure_commits
        @recent_azure_commits ||= azure_client_for_source.commits.map { |commit| parse_azure_commit(commit) }
      end

      sig { returns(T::Array[RecentCommit]) }
      def recent_bitbucket_commits
        @recent_bitbucket_commits ||= bitbucket_client_for_source
                                      .commits(source.repo)
                                      .map { |commit| parse_bitbucket_commit(commit) }
      end

      sig { returns(T::Array[RecentCommit]) }
      def recent_codecommit_commits
        return @recent_codecommit_commits if @recent_codecommit_commits

        response = codecommit_client_for_source.commits(source.repo)
        output = T.cast(response.data, Aws::CodeCommit::Types::BatchGetCommitsOutput)
        @recent_codecommit_commits = (output.commits || []).map do |commit|
          RecentCommit.new(
            message: commit.message,
            author_email: commit.author&.email
          )
        end
      end

      sig { params(commit: Sawyer::Resource).returns(RecentCommit) }
      def parse_github_commit(commit)
        details = sawyer_resource(commit, :commit, "commit details")
        author = sawyer_optional_resource(commit, :author, "author")
        commit_author = sawyer_optional_resource(details, :author, "commit author")
        RecentCommit.new(
          message: sawyer_optional_string(details, :message, "commit message"),
          author_email: commit_author && sawyer_optional_string(commit_author, :email, "author email"),
          author_name: commit_author && sawyer_optional_string(commit_author, :name, "author name"),
          author_type: author && sawyer_optional_string(author, :type, "author type")
        )
      end

      sig { params(commit: ::Gitlab::ObjectifiedHash).returns(RecentCommit) }
      def parse_gitlab_commit(commit)
        RecentCommit.new(
          message: gitlab_optional_string(commit, "message", "commit message"),
          author_email: gitlab_optional_string(commit, "author_email", "author email")
        )
      end

      sig { params(commit: Dependabot::Clients::Azure::JsonObject).returns(RecentCommit) }
      def parse_azure_commit(commit)
        author = object_hash(commit, "author", "Azure author")
        RecentCommit.new(
          message: object_optional_string(commit, "comment", "Azure commit message"),
          author_email: object_optional_string(author, "email", "Azure author email")
        )
      end

      sig { params(commit: Dependabot::Clients::Bitbucket::JsonObject).returns(RecentCommit) }
      def parse_bitbucket_commit(commit)
        author = object_hash(commit, "author", "Bitbucket author")
        raw_author = object_optional_string(author, "raw", "Bitbucket author")
        matches = raw_author&.match(/<(.*)>/)
        RecentCommit.new(
          message: object_optional_string(commit, "message", "Bitbucket commit message"),
          author_email: matches ? T.must(matches[1]) : nil
        )
      end

      sig { params(resource: Sawyer::Resource, key: Symbol, context: String).returns(Sawyer::Resource) }
      def sawyer_resource(resource, key, context)
        value = T.cast(resource[key], Object)
        return value if value.is_a?(Sawyer::Resource)

        raise_bad_commit_response("GitHub", "#{context} must be an object")
      end

      sig { params(resource: Sawyer::Resource, key: Symbol, context: String).returns(T.nilable(Sawyer::Resource)) }
      def sawyer_optional_resource(resource, key, context)
        value = T.cast(resource[key], Object)
        return if value.nil?
        return value if value.is_a?(Sawyer::Resource)

        raise_bad_commit_response("GitHub", "#{context} must be an object or nil")
      end

      sig { params(resource: Sawyer::Resource, key: Symbol, context: String).returns(T.nilable(String)) }
      def sawyer_optional_string(resource, key, context)
        value = T.cast(resource[key], Object)
        return if value.nil?
        return value if value.is_a?(String)

        raise_bad_commit_response("GitHub", "#{context} must be a string or nil")
      end

      sig { params(resource: ::Gitlab::ObjectifiedHash, key: String, context: String).returns(T.nilable(String)) }
      def gitlab_optional_string(resource, key, context)
        value = T.cast(resource[key], Object)
        return if value.nil?
        return value if value.is_a?(String)

        raise_bad_commit_response("GitLab", "#{context} must be a string or nil")
      end

      sig do
        params(object: T::Hash[String, Object], key: String, context: String)
          .returns(T::Hash[String, Object])
      end
      def object_hash(object, key, context)
        value = object[key]
        return T.let(value, T::Hash[String, Object]) if value.is_a?(Hash)

        raise_bad_commit_response(source.provider, "#{context} must be an object")
      end

      sig { params(object: T::Hash[String, Object], key: String, context: String).returns(T.nilable(String)) }
      def object_optional_string(object, key, context)
        value = object[key]
        return if value.nil?
        return value if value.is_a?(String)

        raise_bad_commit_response(source.provider, "#{context} must be a string or nil")
      end

      sig { params(provider: String, message: String).returns(T.noreturn) }
      def raise_bad_commit_response(provider, message)
        raise Dependabot::PrivateSourceBadResponse.new(
          source.url,
          "Malformed #{provider} commit response: #{message}"
        )
      end

      sig { returns(Dependabot::Clients::GithubWithRetries) }
      def github_client_for_source
        @github_client_for_source ||=
          T.let(
            Dependabot::Clients::GithubWithRetries.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::GithubWithRetries)
          )
      end

      sig { returns(Dependabot::Clients::GitlabWithRetries) }
      def gitlab_client_for_source
        @gitlab_client_for_source ||=
          T.let(
            Dependabot::Clients::GitlabWithRetries.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::GitlabWithRetries)
          )
      end

      sig { returns(Dependabot::Clients::Azure) }
      def azure_client_for_source
        @azure_client_for_source ||=
          T.let(
            Dependabot::Clients::Azure.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::Azure)
          )
      end

      sig { returns(Dependabot::Clients::Bitbucket) }
      def bitbucket_client_for_source
        @bitbucket_client_for_source ||=
          T.let(
            Dependabot::Clients::Bitbucket.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::Bitbucket)
          )
      end

      sig { returns(Dependabot::Clients::CodeCommit) }
      def codecommit_client_for_source
        @codecommit_client_for_source ||=
          T.let(
            Dependabot::Clients::CodeCommit.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::CodeCommit)
          )
      end

      sig { returns(String) }
      def package_manager
        @package_manager ||= T.let(
          T.must(dependencies.first).package_manager,
          T.nilable(String)
        )
      end
    end
  end
end
