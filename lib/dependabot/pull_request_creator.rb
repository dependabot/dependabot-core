# frozen_string_literal: true

require "dependabot/metadata_finders"

module Dependabot
  class PullRequestCreator
    require "dependabot/pull_request_creator/github"
    require "dependabot/pull_request_creator/gitlab"
    require "dependabot/pull_request_creator/message_builder"
    require "dependabot/pull_request_creator/branch_namer"
    require "dependabot/pull_request_creator/labeler"

    attr_reader :source, :dependencies, :files, :base_commit,
                :credentials, :pr_message_footer, :custom_labels,
                :author_details, :signature_key, :vulnerabilities_fixed,
                :reviewers, :assignees, :milestone, :branch_name_separator

    def initialize(source:, base_commit:, dependencies:, files:, credentials:,
                   pr_message_footer: nil, custom_labels: nil,
                   author_details: nil, signature_key: nil,
                   reviewers: nil, assignees: nil, milestone: nil,
                   vulnerabilities_fixed: {}, branch_name_separator: "/")
      @dependencies          = dependencies
      @source                = source
      @base_commit           = base_commit
      @files                 = files
      @credentials           = credentials
      @pr_message_footer     = pr_message_footer
      @author_details        = author_details
      @signature_key         = signature_key
      @custom_labels         = custom_labels
      @reviewers             = reviewers
      @assignees             = assignees
      @milestone             = milestone
      @vulnerabilities_fixed = vulnerabilities_fixed
      @branch_name_separator = branch_name_separator

      check_dependencies_have_previous_version
    end

    def check_dependencies_have_previous_version
      return if library? && dependencies.all? { |d| requirements_changed?(d) }
      return if dependencies.all?(&:previous_version)

      raise "Dependencies must have a previous version or changed " \
            "requirement to have a pull request created for them!"
    end

    def create
      case source.provider
      when "github" then github_creator.create
      when "gitlab" then gitlab_creator.create
      else raise "Unsupported provider #{source.provider}"
      end
    end

    private

    def github_creator
      Github.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message_builder.commit_message,
        pr_description: message_builder.pr_message,
        pr_name: message_builder.pr_name,
        author_details: author_details,
        signature_key: signature_key,
        labeler: labeler,
        reviewers: reviewers,
        assignees: assignees,
        milestone: milestone
      )
    end

    def gitlab_creator
      Gitlab.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message_builder.commit_message,
        pr_description: message_builder.pr_message,
        pr_name: message_builder.pr_name,
        author_details: author_details,
        labeler: labeler,
        assignee: assignees&.first
      )
    end

    def message_builder
      @message_builder ||
        MessageBuilder.new(
          source: source,
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
          target_branch: source.branch,
          separator: branch_name_separator
        )
    end

    def labeler
      @labeler ||=
        Labeler.new(
          source: source,
          custom_labels: custom_labels,
          credentials: credentials,
          includes_security_fixes: includes_security_fixes?,
          update_type: update_type
        )
    end

    def library?
      if files.map(&:name).any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
        return true
      end

      dependencies.none?(&:appears_in_lockfile?)
    end

    def includes_security_fixes?
      vulnerabilities_fixed.values.flatten.any?
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    def update_type
      return unless dependencies.any?(&:previous_version)

      precison = dependencies.map do |dep|
        new_version_parts = version(dep).split(".")
        old_version_parts = previous_version(dep)&.split(".") || []
        all_parts = new_version_parts.first(3) + old_version_parts.first(3)
        next 0 unless all_parts.all? { |part| part.to_i.to_s == part }
        next 1 if new_version_parts[0] != old_version_parts[0]
        next 2 if new_version_parts[1] != old_version_parts[1]
        3
      end.min

      case precison
      when 0 then "non-semver"
      when 1 then "major"
      when 2 then "minor"
      when 3 then "patch"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

    def version(dep)
      return dep.version if version_class.correct?(dep.version)
      source = dep.requirements.find { |r| r.fetch(:source) }&.fetch(:source)
      return dep.version unless source&.fetch("type") == "git"
      version_from_ref = source.fetch("ref")&.gsub(/^v/, "")
      return dep.version unless version_from_ref
      return dep.version unless version_class.correct?(version_from_ref)
      version_from_ref
    end

    def previous_version(dep)
      version_str = dep.previous_version
      return version_str if version_class.correct?(version_str)
      source = dep.previous_requirements.
               find { |r| r.fetch(:source) }&.fetch(:source)
      return version_str unless source&.fetch("type") == "git"
      version_from_ref = source.fetch("ref")&.gsub(/^v/, "")
      return version_str unless version_from_ref
      return version_str unless version_class.correct?(version_from_ref)
      version_from_ref
    end

    def version_class
      Utils.version_class_for_package_manager(
        dependencies.first.package_manager
      )
    end

    def requirements_changed?(dependency)
      (dependency.requirements - dependency.previous_requirements).any?
    end
  end
end
