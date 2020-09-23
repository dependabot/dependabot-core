# frozen_string_literal: true

require "octokit"

github_token = ENV["REPOSITORY_ACCESS_TOKEN"]
commit_hash = ENV["COMMIT_HASH"]
project_path = "pix4d/dependabot-core"

client = Octokit::Client.new(access_token: github_token)
pr_list = client.pull_requests(project_path, state: "opened")

pr_list.each do |pr|
  unless (pr.head.sha == commit_hash) &&
         pr.title.include?("[no-changes-to-pix4d-dependabot]")
    next
  end

  commit_title = "Auto-merge pull request #{pr.number} from #{pr.head.ref}"
  commit_msg = "Merge upstream changes to Pix4D fork"

  client.merge_pull_request(
    project_path,
    pr.number,
    commit_msg,
    commit_title: commit_title
  )

  unless client.pull_merged?(project_path, pr.number)
    raise "The PR was not merged correctly"
  end

  # Delete the branch if it exists. If it doesn't exist, swallow the exception.
  begin
    client.delete_branch(project_path, pr.head.ref)
  rescue Octokit::UnprocessableEntity
    nil
  end
end
