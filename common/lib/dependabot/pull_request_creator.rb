# frozen_string_literal: true

require "dependabot/metadata_finders"

module Dependabot
  class PullRequestCreator
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

    # AnnotationError is raised if a PR was created, but failed annotation
    class AnnotationError < StandardError
      attr_reader :cause, :pull_request
      def initialize(cause, pull_request)
        super(cause.message)
        @cause = cause
        @pull_request = pull_request
      end
    end

    attr_reader :source, :dependencies, :files, :base_commit,
                :credentials, :pr_message_header, :pr_message_footer,
                :custom_labels, :author_details, :signature_key,
                :commit_message_options, :vulnerabilities_fixed,
                :reviewers, :assignees, :milestone, :branch_name_separator,
                :branch_name_prefix, :branch_name_max_length, :github_redirection_service,
                :custom_headers, :provider_metadata

    def initialize(source:, base_commit:, dependencies:, files:, credentials:,
                   pr_message_header: nil, pr_message_footer: nil,
                   custom_labels: nil, author_details: nil, signature_key: nil,
                   commit_message_options: {}, vulnerabilities_fixed: {},
                   reviewers: nil, assignees: nil, milestone: nil,
                   branch_name_separator: "/", branch_name_prefix: "dependabot",
                   branch_name_max_length: nil, label_language: false,
                   automerge_candidate: false,
                   github_redirection_service: DEFAULT_GITHUB_REDIRECTION_SERVICE,
                   custom_headers: nil, require_up_to_date_base: false,
                   provider_metadata: {}, message: nil)
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

      check_dependencies_have_previous_version
    end

    def check_dependencies_have_previous_version
      return if dependencies.all? { |d| requirements_changed?(d) }
      return if dependencies.all?(&:previous_version)

      raise "Dependencies must have a previous version or changed " \
            "requirement to have a pull request created for them!"
    end

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

    def label_language?
      @label_language
    end

    def automerge_candidate?
      @automerge_candidate
    end

    def require_up_to_date_base?
      @require_up_to_date_base
    end

    def github_creator
      Github.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message.commit_message,
        pr_description: message.pr_message,
        pr_name: message.pr_name,
        author_details: author_details,
        signature_key: signature_key,
        labeler: labeler,
        reviewers: reviewers,
        assignees: assignees,
        milestone: milestone,
        custom_headers: custom_headers,
        require_up_to_date_base: require_up_to_date_base?
      )
    end

    def gitlab_creator
      Gitlab.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message.commit_message,
        pr_description: message.pr_message,
        pr_name: message.pr_name,
        author_details: author_details,
        labeler: labeler,
        approvers: reviewers,
        assignees: assignees,
        milestone: milestone,
        target_project_id: provider_metadata[:target_project_id]
      )
    end

    def azure_creator
      Azure.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message.commit_message,
        pr_description: message.pr_message,
        pr_name: message.pr_name,
        author_details: author_details,
        labeler: labeler,
        reviewers: reviewers,
        assignees: assignees,
        work_item: provider_metadata&.fetch(:work_item, nil)
      )
    end

    def bitbucket_creator
      Bitbucket.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message.commit_message,
        pr_description: message.pr_message,
        pr_name: message.pr_name,
        author_details: author_details,
        labeler: nil,
        work_item: provider_metadata&.fetch(:work_item, nil)
      )
    end

    def codecommit_creator
      Codecommit.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message.commit_message,
        pr_description: message.pr_message,
        pr_name: message.pr_name,
        author_details: author_details,
        labeler: labeler,
        require_up_to_date_base: require_up_to_date_base?
      )
    end

    def message
      @message ||=
        MessageBuilder.new(
          source: source,
          dependencies: dependencies,
          files: files,
          credentials: credentials,
          commit_message_options: commit_message_options,
          pr_message_header: pr_message_header,
          pr_message_footer: pr_message_footer,
          vulnerabilities_fixed: vulnerabilities_fixed,
          github_redirection_service: github_redirection_service
        )
    end

    def branch_namer
      @branch_namer ||=
        BranchNamer.new(
          dependencies: dependencies,
          files: files,
          target_branch: source.branch,
          separator: branch_name_separator,
          prefix: branch_name_prefix,
          max_length: branch_name_max_length
        )
    end

    def labeler
      @labeler ||=
        Labeler.new(
          source: source,
          custom_labels: custom_labels,
          credentials: credentials,
          includes_security_fixes: includes_security_fixes?,
          dependencies: dependencies,
          label_language: label_language?,
          automerge_candidate: automerge_candidate?
        )
    end

    def includes_security_fixes?
      vulnerabilities_fixed.values.flatten.any?
    end

    def requirements_changed?(dependency)
      (dependency.requirements - dependency.previous_requirements).any?
    end
  end
end
