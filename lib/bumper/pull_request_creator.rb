require "github"

class PullRequestCreator
  attr_reader :watched_repo, :dependency, :files

  def initialize(repo:, dependency:, files:)
    @dependency = dependency
    @watched_repo = repo
    @files = files
  end

  def create
    return unless create_branch
    files.each { |file| update_file(file) }
    create_pull_request
  end

  private

  def create_branch
    Github.client.create_ref(
      watched_repo,
      "heads/#{new_branch_name}",
      default_branch_sha
    )
  rescue Octokit::UnprocessableEntity
    nil
  end

  def update_file(file)
    # GitHub's API makes it hard to create a new commit with multiple files.
    # TODO: use https://developer.github.com/v3/git/commits/#create-a-commit
    current_file = Github.client.contents(watched_repo, path: file.name)
    Github.client.update_contents(
      watched_repo,
      file.name,
      "Updating #{file.name}",
      current_file.sha,
      file.content,
      branch: new_branch_name
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
            "#{dependency.version}"
    else
      msg = "Bumps #{dependency.name} to #{dependency.version}"
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

  def default_branch_sha
    Github.client.ref(watched_repo, "heads/#{default_branch}").object.sha
  end

  def new_branch_name
    @new_branch_name ||= "bump_#{dependency.name}_to_#{dependency.version}"
  end
end
