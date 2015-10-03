require "github"

class PullRequestCreator
  attr_reader :repo, :dependency, :files

  def initialize(repo:, dependency:, files:)
    @dependency = dependency
    @repo = repo
    @files = files
  end

  private

  def create
    create_branch
    files.each { |file| update_file(file) }
    create_pull_request
  end

  def default_branch
    @default_branch ||= Github.client.repository("#{repo}").default_branch
  end

  def default_branch_sha
    Github.client.ref(repo, "heads/#{default_branch}").object.sha
  end

  def new_branch_name
    @new_branch_name ||= "bump_#{dependency.name}_to_#{dependency.version}"
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

  def create_branch
    Github.client.create_ref(
      repo,
      "heads/#{new_branch_name}",
      default_branch_sha
    )
  end

  def create_pull_request
    Github.client.create_pull_request(
      repo,
      default_branch,
      new_branch_name,
      "Bump #{dependency.name} to #{dependency.version}",
      "<3 bump"
    )
  end
end
