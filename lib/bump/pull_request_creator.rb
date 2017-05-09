# frozen_string_literal: true
require "bump/dependency_metadata_finders"

module Bump
  class PullRequestCreator
    attr_reader :watched_repo, :dependency, :files, :base_commit, :github_client

    def initialize(repo:, base_commit:, dependency:, files:, github_client:)
      @dependency = dependency
      @watched_repo = repo
      @base_commit = base_commit
      @files = files
      @github_client = github_client
    end

    def create
      return if branch_exists?

      commit = create_commit
      create_branch(commit)

      create_pull_request
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
        {
          path: file.path.sub(%r{^/}, ""),
          mode: "100644",
          type: "blob",
          content: file.content
        }
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
    end

    def create_pull_request
      github_client.create_pull_request(
        watched_repo,
        default_branch,
        new_branch_name,
        pr_name,
        pr_message
      )
    end

    def commit_message
      pr_name + "\n\n" + pr_message
    end

    def pr_name
      "Bump #{dependency.name} to #{dependency.version}"
    end

    def pr_message
      msg =
        if dependency_metadata_finder.github_repo_url
          "Bumps [#{dependency.name}]"\
          "(#{dependency_metadata_finder.github_repo_url}) to "\
          "#{dependency.version}."
        else
          "Bumps #{dependency.name} to #{dependency.version}."
        end

      if dependency_metadata_finder.release_url
        msg += "\n- [Release notes](#{dependency_metadata_finder.release_url})"
      end

      if dependency_metadata_finder.changelog_url
        msg += "\n- [Changelog](#{dependency_metadata_finder.changelog_url})"
      end

      if dependency_metadata_finder.github_repo_url
        msg += "\n- [Commits](#{dependency_metadata_finder.github_compare_url})"
      end

      msg
    end

    def default_branch
      @default_branch ||= github_client.repository(watched_repo).default_branch
    end

    def new_branch_name
      "bump_#{dependency.name}_to_#{dependency.version}"
    end

    def dependency_metadata_finder
      @dependency_metadata_finder ||=
        DependencyMetadataFinders.for_language(dependency.language).
        new(dependency: dependency, github_client: github_client)
    end
  end
end
