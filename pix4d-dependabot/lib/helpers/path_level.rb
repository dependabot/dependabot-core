# frozen_string_literal: true

def recursive_path(project_data, github_token)
  if project_data["module"] == "docker"

    client = Octokit::Client.new(access_token: github_token)
    branch = client.branch(project_data["repo"], project_data["branch"])
    tree = client.tree(project_data["repo"], branch.commit.sha, recursive: true).tree

    selected_paths = tree.select { |f| f.path.include?(project_data["dependency_dir"].to_s) }.
                     select { |f| f.path.include?("Dockerfile") }.
                     map(&:path)

    input_files_path = []
    selected_paths.each do |path|
      path.slice! "/Dockerfile"
      input_files_path << path
    end
  else
    input_files_path = [project_data["dependency_dir"]]
  end
end
