# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/credential"

module Dependabot
  class PullRequestCreator
    extend T::Sig

    require "dependabot/pull_request_creator/azure"
    require "dependabot/pull_request_creator/bitbucket"
    require "dependabot/pull_request_creator/codecommit"
    require "dependabot/pull_request_creator/github"
    require "dependabot/pull_request_creator/gitlab"
    require "dependabot/pull_request_creator/message_builder"
    require "dependabot/pull_request_creator/branch_namer"
    require "dependabot/pull_request_creator/labeler"

    # Dependabot programmatically creates PRs which often include a large
    # number of links to objects on `github.com`. GitHub hydrates these into
    # rich links that leave a 'mention' on target Issues/Pull Requests.
    #
    # Due to the volume and nature of Dependabot PRs, these mentions are not
    # useful and can overwhelm maintainers, so we use a redirection service
    # to avoid enrichment.
    #
    # If you wish to disable this behaviour when using Dependabot Core directly,
    # pass a nil value when initialising this class.
    DEFAULT_GITHUB_REDIRECTION_SERVICE = "redirect.github.com"

    class RepoNotFound < StandardError; end

    class RepoArchived < StandardError; end

    class RepoDisabled < StandardError; end

    class NoHistoryInCommon < StandardError; end

    class UnmergedPRExists < StandardError; end

    class BaseCommitNotUpToDate < StandardError; end

    class UnexpectedError < StandardError; end

    # AnnotationError is raised if a PR was created, but failed annotation
    class AnnotationError < StandardError
      extend T::Sig

      sig { returns(StandardError) }
      attr_reader :cause

      # TODO: Currently, this error is only used by the GitHub PR creator.
      #       An Octokit update will likely give this a proper type,
      #       but we should consider a `Dependabot::PullRequest` type.
      sig { returns(Sawyer::Resource) }
      attr_reader :pull_request

      sig { params(cause: StandardError, pull_request: Sawyer::Resource).void }
      def initialize(cause, pull_request)
        super(cause.message)
        @cause = cause
        @pull_request = pull_request
      end
    end

    sig { returns(Dependabot::Source) }
    attr_reader :source

    sig { returns(T::Array[Dependabot::Dependency]) }
    attr_reader :dependencies

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    attr_reader :files

    sig { returns(String) }
    attr_reader :base_commit

    sig { returns(T::Array[Dependabot::Credential]) }
    attr_reader :credentials

    sig { returns(T.nilable(String)) }
    attr_reader :pr_message_header

    sig { returns(T.nilable(String)) }
    attr_reader :pr_message_footer

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :custom_labels

    sig { returns(T.nilable(T::Hash[Symbol, String])) }
    attr_reader :author_details

    sig { returns(T.nilable(String)) }
    attr_reader :signature_key

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :commit_message_options

    sig { returns(T::Hash[String, String]) }
    attr_reader :vulnerabilities_fixed

    AzureReviewers = T.type_alias { T.nilable(T::Array[String]) }
    GithubReviewers = T.type_alias { T.nilable(T::Hash[String, T::Array[String]]) }
    GitLabReviewers = T.type_alias { T.nilable(T::Hash[Symbol, T::Array[Integer]]) }
    Reviewers = T.type_alias { T.any(AzureReviewers, GithubReviewers, GitLabReviewers) }

    sig { returns(Reviewers) }
    attr_reader :reviewers

    sig { returns(T.nilable(T.any(T::Array[String], T::Array[Integer]))) }
    attr_reader :assignees

    sig { returns(T.nilable(T.any(T::Array[String], Integer))) }
    attr_reader :milestone

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :existing_branches

    sig { returns(String) }
    attr_reader :branch_name_separator

    sig { returns(String) }
    attr_reader :branch_name_prefix

    sig { returns(T.nilable(Integer)) }
    attr_reader :branch_name_max_length

    sig { returns(String) }
    attr_reader :github_redirection_service

    sig { returns(T.nilable(T::Hash[String, String])) }
    attr_reader :custom_headers

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    attr_reader :provider_metadata

    sig { returns(T.nilable(Dependabot::DependencyGroup)) }
    attr_reader :dependency_group

    sig { returns(T.nilable(Integer)) }
    attr_reader :pr_message_max_length

    sig { returns(T.nilable(Encoding)) }
    attr_reader :pr_message_encoding

    sig do
      params(
        source: Dependabot::Source,
        base_commit: String,
        dependencies: T::Array[Dependabot::Dependency],
        files: T::Array[Dependabot::DependencyFile],
        credentials: T::Array[Dependabot::Credential],
        pr_message_header: T.nilable(String),
        pr_message_footer: T.nilable(String),
        custom_labels: T.nilable(T::Array[String]),
        author_details: T.nilable(T::Hash[Symbol, String]),
        signature_key: T.nilable(String),
        commit_message_options: T::Hash[Symbol, T.untyped],
        vulnerabilities_fixed: T::Hash[String, String],
        reviewers: Reviewers,
        assignees: T.nilable(T.any(T::Array[String], T::Array[Integer])),
        milestone: T.nilable(T.any(T::Array[String], Integer)),
        existing_branches: T.nilable(T::Array[String]),
        branch_name_separator: String,
        branch_name_prefix: String,
        branch_name_max_length: T.nilable(Integer),
        label_language: T::Boolean,
        automerge_candidate: T::Boolean,
        github_redirection_service: String,
        custom_headers: T.nilable(T::Hash[String, String]),
        require_up_to_date_base: T::Boolean,
        provider_metadata: T.nilable(T::Hash[Symbol, T.untyped]),
        message: T.nilable(
          T.any(Dependabot::PullRequestCreator::Message, Dependabot::PullRequestCreator::MessageBuilder)
        ),
        dependency_group: T.nilable(Dependabot::DependencyGroup),
        pr_message_max_length: T.nilable(Integer),
        pr_message_encoding: T.nilable(Encoding)
      )
        .void
    end
    def initialize(source:, base_commit:, dependencies:, files:, credentials:,
                   pr_message_header: nil, pr_message_footer: nil,
                   custom_labels: nil, author_details: nil, signature_key: nil,
                   commit_message_options: {}, vulnerabilities_fixed: {},
                   reviewers: nil, assignees: nil, milestone: nil,
                   existing_branches: [], branch_name_separator: "/", 
                   branch_name_prefix: "dependabot", branch_name_max_length: nil, 
                   label_language: false, automerge_candidate: false,
                   github_redirection_service: DEFAULT_GITHUB_REDIRECTION_SERVICE,
                   custom_headers: nil, require_up_to_date_base: false,
                   provider_metadata: {}, message: nil, dependency_group: nil, pr_message_max_length: nil,
                   pr_message_encoding: nil)
      @dependencies               = dependencies
      @source                     = source
      @base_commit                = base_commit
      @files                      = files
      @credentials                = credentials
      @pr_message_header          = pr_message_header
      @pr_message_footer          = pr_message_footer
      @author_details             = author_details
      @signature_key              = signature_key
      @commit_message_options     = commit_message_options
      @custom_labels              = custom_labels
      @reviewers                  = reviewers
      @assignees                  = assignees
      @milestone                  = milestone
      @vulnerabilities_fixed      = vulnerabilities_fixed
      @existing_branches          = existing_branches
      @branch_name_separator      = branch_name_separator
      @branch_name_prefix         = branch_name_prefix
      @branch_name_max_length     = branch_name_max_length
      @label_language             = label_language
      @automerge_candidate        = automerge_candidate
      @github_redirection_service = github_redirection_service
      @custom_headers             = custom_headers
      @require_up_to_date_base    = require_up_to_date_base
      @provider_metadata          = provider_metadata
      @message                    = message
      @dependency_group           = dependency_group
      @pr_message_max_length      = pr_message_max_length
      @pr_message_encoding        = pr_message_encoding

      check_dependencies_have_previous_version
    end

    sig { void }
    def check_dependencies_have_previous_version
      return if dependencies.all? { |d| requirements_changed?(d) }
      return if dependencies.all?(&:previous_version)

      raise "Dependencies must have a previous version or changed " \
            "requirement to have a pull request created for them!"
    end

    # TODO: This returns client-specific objects.
    # We should create a standard interface (`Dependabot::PullRequest`) and
    # then convert to that
    sig { returns(T.untyped) }
    def create
      case source.provider
      when "github" then github_creator.create
      when "gitlab" then gitlab_creator.create
      when "azure" then azure_creator.create
      when "bitbucket" then bitbucket_creator.create
      when "codecommit" then codecommit_creator.create
      else raise "Unsupported provider #{source.provider}"
      end
    end

    private

    sig { returns(T::Boolean) }
    def label_language?
      @label_language
    end

    sig { returns(T::Boolean) }
    def automerge_candidate?
      @automerge_candidate
    end

    sig { returns(T::Boolean) }
    def require_up_to_date_base?
      @require_up_to_date_base
    end

    sig { returns(Dependabot::PullRequestCreator::Github) }
    def github_creator
      Github.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: T.must(message.commit_message),
        pr_description: T.must(message.pr_message),
        pr_name: T.must(message.pr_name),
        author_details: author_details,
        signature_key: signature_key,
        labeler: labeler,
        reviewers: T.cast(reviewers, GithubReviewers),
        assignees: T.cast(assignees, T.nilable(T::Array[String])),
        milestone: T.cast(milestone, T.nilable(Integer)),
        custom_headers: custom_headers,
        require_up_to_date_base: require_up_to_date_base?
      )
    end

    sig { returns(Dependabot::PullRequestCreator::Gitlab) }
    def gitlab_creator
      Gitlab.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: T.must(message.commit_message),
        pr_description: T.must(message.pr_message),
        pr_name: T.must(message.pr_name),
        author_details: author_details,
        labeler: labeler,
        approvers: T.cast(reviewers, T.nilable(T::Hash[Symbol, T::Array[Integer]])),
        assignees: T.cast(assignees, T.nilable(T::Array[Integer])),
        milestone: milestone,
        target_project_id: T.cast(provider_metadata&.fetch(:target_project_id, nil), T.nilable(Integer))
      )
    end

    sig { returns(Dependabot::PullRequestCreator::Azure) }
    def azure_creator
      Azure.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: T.must(message.commit_message),
        pr_description: T.must(message.pr_message),
        pr_name: T.must(message.pr_name),
        author_details: author_details,
        labeler: labeler,
        reviewers: T.cast(reviewers, AzureReviewers),
        assignees: T.cast(assignees, T.nilable(T::Array[String])),
        work_item: T.cast(provider_metadata&.fetch(:work_item, nil), T.nilable(Integer))
      )
    end

    sig { returns(Dependabot::PullRequestCreator::Bitbucket) }
    def bitbucket_creator
      Bitbucket.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: T.must(message.commit_message),
        pr_description: T.must(message.pr_message),
        pr_name: T.must(message.pr_name),
        author_details: author_details,
        labeler: nil,
        work_item: T.cast(provider_metadata&.fetch(:work_item, nil), T.nilable(Integer))
      )
    end

    sig { returns(Dependabot::PullRequestCreator::Codecommit) }
    def codecommit_creator
      Codecommit.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: T.must(message.commit_message),
        pr_description: T.must(message.pr_message),
        pr_name: T.must(message.pr_name),
        author_details: author_details,
        labeler: labeler,
        require_up_to_date_base: require_up_to_date_base?
      )
    end

    sig { returns(T.any(Dependabot::PullRequestCreator::Message, Dependabot::PullRequestCreator::MessageBuilder)) }
    def message
      return @message unless @message.nil?

      case source.provider
      when "github"
        @pr_message_max_length = Github::PR_DESCRIPTION_MAX_LENGTH if @pr_message_max_length.nil?
      when "azure"
        @pr_message_max_length = Azure::PR_DESCRIPTION_MAX_LENGTH if @pr_message_max_length.nil?
        @pr_message_encoding = Azure::PR_DESCRIPTION_ENCODING if @pr_message_encoding.nil?
      when "codecommit"
        @pr_message_max_length = Codecommit::PR_DESCRIPTION_MAX_LENGTH if @pr_message_max_length.nil?
      when "bitbucket"
        @pr_message_max_length = Bitbucket::PR_DESCRIPTION_MAX_LENGTH if @pr_message_max_length.nil?
      end

      @message = MessageBuilder.new(
        source: source,
        dependencies: dependencies,
        files: files,
        credentials: credentials,
        commit_message_options: commit_message_options,
        pr_message_header: pr_message_header,
        pr_message_footer: pr_message_footer,
        vulnerabilities_fixed: vulnerabilities_fixed,
        github_redirection_service: github_redirection_service,
        dependency_group: dependency_group,
        pr_message_max_length: pr_message_max_length,
        pr_message_encoding: pr_message_encoding
      )
    end

    sig { returns(Dependabot::PullRequestCreator::BranchNamer) }
    def branch_namer
      @branch_namer ||= T.let(
        BranchNamer.new(
          dependencies: dependencies,
          files: files,
          target_branch: source.branch,
          dependency_group: dependency_group,
          existing_branches: existing_branches,
          separator: branch_name_separator,
          prefix: branch_name_prefix,
          max_length: branch_name_max_length,
          includes_security_fixes: includes_security_fixes?
        ),
        T.nilable(Dependabot::PullRequestCreator::BranchNamer)
      )
    end

    sig { returns(Dependabot::PullRequestCreator::Labeler) }
    def labeler
      @labeler ||= T.let(
        Labeler.new(
          source: source,
          custom_labels: custom_labels,
          credentials: credentials,
          includes_security_fixes: includes_security_fixes?,
          dependencies: dependencies,
          label_language: label_language?,
          automerge_candidate: automerge_candidate?
        ),
        T.nilable(Dependabot::PullRequestCreator::Labeler)
      )
    end

    sig { returns(T::Boolean) }
    def includes_security_fixes?
      vulnerabilities_fixed.values.flatten.any?
    end

    sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
    def requirements_changed?(dependency)
      (dependency.requirements - T.must(dependency.previous_requirements)).any?
    end
  end
end
