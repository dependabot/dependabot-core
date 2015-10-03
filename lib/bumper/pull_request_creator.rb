require "github"

class PullRequestCreator
  CHANGELOG_NAMES = %w(changelog history)

  attr_reader :repo, :dependency, :files

  def initialize(repo:, dependency:, files:)
    @dependency = dependency
    @repo = repo
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
      repo,
      "heads/#{new_branch_name}",
      default_branch_sha
    )
  rescue Octokit::UnprocessableEntity
    nil
  end

  def update_file(file)
    # GitHub's API makes it hard to create a new commit with multiple files.
    # TODO: use https://developer.github.com/v3/git/commits/#create-a-commit
    current_file = Github.client.contents(repo, path: file.name)
    Github.client.update_contents(
      repo,
      file.name,
      "Updating #{file.name}",
      current_file.sha,
      file.content,
      branch: new_branch_name
    )
  end

  def create_pull_request
    Github.client.create_pull_request(
      repo,
      default_branch,
      new_branch_name,
      "Bump #{dependency.name} to #{dependency.version}",
      pr_message
    )
  end

  def pr_message
    msg = "Bumps [#{dependency.name}](#{repo_url}) to #{dependency.version}"
    msg += "\n- [Changelog](#{changelog_url})" if changelog_url
    msg + "\n- [Commits](#{commits_url})"
  end

  def default_branch
    @default_branch ||= repo_details.default_branch
  end

  def default_branch_sha
    Github.client.ref(repo, "heads/#{default_branch}").object.sha
  end

  def new_branch_name
    @new_branch_name ||= "bump_#{dependency.name}_to_#{dependency.version}"
  end

  def changelog_url
    files = Github.client.contents(repo)
    file = files.find { |f| CHANGELOG_NAMES.any? { |w| f.name =~ /#{w}/i } }

    file.nil? ? nil : file.url
  end

  def repo_url
    repo_details.url
  end

  def commits_url
    repo_url + "/commits"
  end

  def repo_details
    @repo_details ||= Github.client.repository(repo)
  end
end
