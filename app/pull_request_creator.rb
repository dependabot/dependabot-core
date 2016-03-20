require "./lib/github"

class PullRequestCreator
  attr_reader :watched_repo, :dependency, :files, :base_commit

  def initialize(repo:, base_commit:, dependency:, files:)
    @dependency = dependency
    @watched_repo = repo
    @base_commit = base_commit
    @files = files
  end

  def create
    return if branch_exists?

    commit = create_commit
    create_branch(commit)

    create_pull_request
  end

  private

  def branch_exists?
    Github.client.ref(watched_repo, "heads/#{new_branch_name}")
    true
  rescue Octokit::NotFound
    false
  end

  def create_commit
    tree = create_tree

    Github.client.create_commit(
      watched_repo,
      "Bump #{dependency.name} to #{dependency.version}",
      tree.sha,
      base_commit
    )
  end

  def create_tree
    file_trees = files.map do |file|
      { path: file.name, mode: "100644", type: "blob", content: file.content }
    end

    Github.client.create_tree(
      watched_repo,
      file_trees,
      base_tree: base_commit
    )
  end

  def create_branch(commit)
    Github.client.create_ref(
      watched_repo,
      "heads/#{new_branch_name}",
      commit.sha
    )
  end

  def create_pull_request
    Github.client.create_pull_request(
      watched_repo,
      default_branch,
      new_branch_name,
      "Bump #{dependency.name} to #{dependency.version}",
      pr_message
    )
  end

  def pr_message
    if dependency.github_repo_url
      msg = "Bumps [#{dependency.name}](#{dependency.github_repo_url}) to "\
            "#{dependency.version}."
    else
      msg = "Bumps #{dependency.name} to #{dependency.version}."
    end

    if dependency.changelog_url
      msg += "\n- [Changelog](#{dependency.changelog_url})"
    end

    if dependency.github_repo_url
      msg += "\n- [Commits](#{dependency.github_repo_url + '/commits'})"
    end

    msg
  end

  def default_branch
    @default_branch ||= Github.client.repository(watched_repo).default_branch
  end

  def new_branch_name
    "bump_#{dependency.name}_to_#{dependency.version}"
  end
end
