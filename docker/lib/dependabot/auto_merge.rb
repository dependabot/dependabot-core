# frozen_string_literal: true

# Automatically merge a pull request to update base Docker image
# for Dockerfiles found in linux-image-build repository
def auto_merge(pr_number,
               pr_branch,
               project_path,
               github_token)

  commit_title = "[Dependabot Docker] Update base Docker image (automerged)"
  client = Octokit::Client.new(access_token: github_token)
  client.merge_pull_request(
    project_path,
    pr_number,
    "Update base Docker image",
    commit_title: commit_title
  )

  unless client.pull_merged?(project_path, pr_number)
    raise "The PR was not merged correctly"
  end

  # Delete the branch if it exists. If it doesn't exist, swallow the exception.
  begin
    client.delete_branch(project_path, pr_branch)
  rescue Octokit::UnprocessableEntity
    nil
  end
end
