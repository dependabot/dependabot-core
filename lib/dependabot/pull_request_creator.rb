# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/update_checkers"
require "octokit"

module Dependabot
  class PullRequestCreator
    attr_reader :watched_repo, :dependency, :files, :base_commit,
                :github_client, :pr_message_footer

    def initialize(repo:, base_commit:, dependency:, files:, github_client:,
                   pr_message_footer: nil)
      @dependency = dependency
      @watched_repo = repo
      @base_commit = base_commit
      @files = files
      @github_client = github_client
      @pr_message_footer = pr_message_footer

      check_dependency_has_previous_version
    end

    def check_dependency_has_previous_version
      return if library? && requirements_changed?
      return if dependency.previous_version

      raise "Dependency must have a previous version or changed " \
            "requirement to have a pull request created for it!"
    end

    def create
      return if branch_exists?

      commit = create_commit
      return unless create_branch(commit)

      create_label unless dependencies_label_exists?

      pull_request = create_pull_request

      add_label_to_pull_request(pull_request)

      pull_request
    end

    private

    def branch_exists?
      github_client.ref(watched_repo, "heads/#{new_branch_name}")
      true
    rescue Octokit::NotFound
      false
    end

    def create_commit
      tree = create_tree

      github_client.create_commit(
        watched_repo,
        commit_message,
        tree.sha,
        base_commit
      )
    end

    def create_tree
      file_trees = files.map do |file|
        if file.type == "file"
          {
            path: file.path.sub(%r{^/}, ""),
            mode: "100644",
            type: "blob",
            content: file.content
          }
        elsif file.type == "submodule"
          {
            path: file.path.sub(%r{^/}, ""),
            mode: "160000",
            type: "commit",
            sha: file.content
          }
        else
          raise "Unknown file type #{file.type}"
        end
      end

      github_client.create_tree(
        watched_repo,
        file_trees,
        base_tree: base_commit
      )
    end

    def create_branch(commit)
      github_client.create_ref(
        watched_repo,
        "heads/#{new_branch_name}",
        commit.sha
      )
    rescue Octokit::UnprocessableEntity => error
      # Return quietly in the case of a race
      return nil if error.message.match?(/Reference already exists/)
      raise
    end

    def dependencies_label_exists?
      github_client.
        labels(watched_repo, per_page: 100).
        map(&:name).
        include?("dependencies")
    end

    def create_label
      github_client.add_label(watched_repo, "dependencies", "0025ff")
    rescue Octokit::UnprocessableEntity => error
      raise unless error.errors.first.fetch(:code) == "already_exists"
    end

    def add_label_to_pull_request(pull_request)
      github_client.add_labels_to_an_issue(
        watched_repo,
        pull_request.number,
        ["dependencies"]
      )
    end

    def create_pull_request
      github_client.create_pull_request(
        watched_repo,
        default_branch,
        new_branch_name,
        pr_name,
        pr_message_with_custom_footer
      )
    end

    def commit_message
      pr_name + "\n\n" + pr_message
    end

    def pr_name
      return library_pr_name if library?

      base = "Bump #{dependency.name} from #{previous_version} " \
             "to #{new_version}"
      return base if files.first.directory == "/"

      base + " in #{files.first.directory}"
    end

    def library_pr_name
      "Update #{dependency.name} requirement to #{new_library_requirement}"
    end

    def pr_message
      return library_pr_message if library?

      msg = if source_url
              "Bumps [#{dependency.name}](#{source_url}) "
            else
              "Bumps #{dependency.name} "
            end

      msg += "from #{previous_version} to #{new_version}."
      msg += "\n- [Release notes](#{release_url})" if release_url
      msg += "\n- [Changelog](#{changelog_url})" if changelog_url
      msg += "\n- [Commits](#{commits_url})" if commits_url
      msg
    end

    def library_pr_message
      msg = "Updates the requirements on "
      msg += if source_url
               "[#{dependency.name}](#{source_url}) "
             else
               "#{dependency.name} "
             end

      msg += "to permit the latest version."
      msg += "\n- [Release notes](#{release_url})" if release_url
      msg += "\n- [Changelog](#{changelog_url})" if changelog_url
      msg
    end

    def pr_message_with_custom_footer
      return pr_message unless pr_message_footer
      pr_message + "\n\n#{pr_message_footer}"
    end

    def default_branch
      @default_branch ||= github_client.repository(watched_repo).default_branch
    end

    def new_branch_name
      path = ["dependabot", dependency.package_manager, files.first.directory]
      path = path.compact

      if library?
        File.join(*path, "#{dependency.name}-#{sanitized_requirement}")
      else
        File.join(*path, "#{dependency.name}-#{new_version}")
      end
    end

    def sanitized_requirement
      new_library_requirement.
        delete(" ").
        gsub("!=", "neq-").
        gsub(">=", "gte-").
        gsub("<=", "lte-").
        gsub("~>", "tw-").
        gsub("=", "eq-").
        gsub(">", "gt-").
        gsub("<", "lt-").
        gsub(",", "-and-")
    end

    def release_url
      metadata_finder.release_url
    end

    def changelog_url
      metadata_finder.changelog_url
    end

    def commits_url
      metadata_finder.commits_url
    end

    def source_url
      metadata_finder.source_url
    end

    def metadata_finder
      @metadata_finder ||=
        MetadataFinders.
        for_package_manager(dependency.package_manager).
        new(dependency: dependency, github_client: github_client)
    end

    def previous_version
      if dependency.previous_version.match?(/^[0-9a-f]{40}$/)
        dependency.previous_version[0..5]
      else
        dependency.previous_version
      end
    end

    def new_version
      if dependency.version.match?(/^[0-9a-f]{40}$/)
        dependency.version[0..5]
      else
        dependency.version
      end
    end

    def new_library_requirement
      updated_reqs = dependency.requirements - dependency.previous_requirements

      gemspec = updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
      return gemspec[:requirement] if gemspec
      updated_reqs.first[:requirement]
    end

    def library?
      if files.map(&:name).any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
        return true
      end

      !dependency.appears_in_lockfile?
    end

    def requirements_changed?
      (dependency.requirements - dependency.previous_requirements).any?
    end
  end
end
