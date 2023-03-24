# TODO: PR Comment
# We needed to tweak a few things in the Dependabot::PullRequestCreator::Bitbucket
# class, so I used it as a base class and changed the methods as needed.
#
# Question: Is it better to have a dependency on this base class and suffer if it
# changes in a way that hurts us or should we copy the whole class so we own it?
class BitbucketServerPullRequestCreator < Dependabot::PullRequestCreator::Bitbucket
  def create_commit
    author = author_details&.slice(:name, :email)
    author = nil unless author&.any?

    source.ext_provider.client.create_commit(
      source.repo,
      branch_name,
      base_commit,
      commit_message,
      files,
      author
    )
  end

  def create_pull_request
    source.ext_provider.client.create_pull_request(
      source.repo,
      pr_name,
      branch_name,
      source.branch || default_branch,
      pr_description,
      nil,
      work_item
    )
  end

  def default_branch
    @default_branch ||=
      source.ext_provider.client.fetch_default_branch(source.repo)
  end
end
