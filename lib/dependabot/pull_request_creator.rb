# frozen_string_literal: true

require "dependabot/metadata_finders"

module Dependabot
  class PullRequestCreator
    require "dependabot/pull_request_creator/github"
    require "dependabot/pull_request_creator/message_builder"
    require "dependabot/pull_request_creator/branch_namer"

    attr_reader :repo_name, :dependencies, :files, :base_commit,
                :credentials, :pr_message_footer, :target_branch,
                :author_details, :signature_key, :custom_labels,
                :vulnerabilities_fixed, :reviewers, :assignees

    def initialize(repo:, base_commit:, dependencies:, files:, credentials:,
                   pr_message_footer: nil, target_branch: nil,
                   custom_labels: nil, author_details: nil, signature_key: nil,
                   reviewers: nil, assignees: nil, vulnerabilities_fixed: {})
      @dependencies          = dependencies
      @repo_name             = repo
      @base_commit           = base_commit
      @files                 = files
      @credentials           = credentials
      @pr_message_footer     = pr_message_footer
      @target_branch         = target_branch
      @author_details        = author_details
      @signature_key         = signature_key
      @custom_labels         = custom_labels
      @reviewers             = reviewers
      @assignees             = assignees
      @vulnerabilities_fixed = vulnerabilities_fixed

      check_dependencies_have_previous_version
    end

    def check_dependencies_have_previous_version
      return if library? && dependencies.all? { |d| requirements_changed?(d) }
      return if dependencies.all?(&:previous_version)

      raise "Dependencies must have a previous version or changed " \
            "requirement to have a pull request created for them!"
    end

    def create
      Github.new(
        repo_name: repo_name,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        target_branch: target_branch,
        credentials: credentials,
        files: files,
        commit_message: message_builder.commit_message,
        pr_description: message_builder.pr_message,
        pr_name: message_builder.pr_name,
        author_details: author_details,
        signature_key: signature_key,
        custom_labels: custom_labels,
        reviewers: reviewers,
        assignees: assignees
      ).create
    end

    private

    def message_builder
      @message_builder ||
        MessageBuilder.new(
          repo_name: repo_name,
          dependencies: dependencies,
          files: files,
          credentials: credentials,
          author_details: author_details,
          pr_message_footer: pr_message_footer,
          vulnerabilities_fixed: vulnerabilities_fixed
        )
    end

    def branch_namer
      @branch_namer ||=
        BranchNamer.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch
        )
    end

    def library?
      if files.map(&:name).any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
        return true
      end

      dependencies.none?(&:appears_in_lockfile?)
    end

    def requirements_changed?(dependency)
      (dependency.requirements - dependency.previous_requirements).any?
    end
  end
end
