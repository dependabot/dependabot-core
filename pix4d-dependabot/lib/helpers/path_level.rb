# frozen_string_literal: true

def select_path_per_directory(git_tree, directory)
  files = git_tree.select do |f|
    f.path.include?(directory.delete_prefix("/").to_s) && f.path.include?("Dockerfile")
  end

  files.map { |item| item["path"] }
end

def recursive_path(project_data, github_token)
  if project_data["module"] == "docker"
    selected_paths = []
    input_files_path = []

    client = Octokit::Client.new(access_token: github_token)
    branch = client.branch(project_data["repo"], project_data["branch"])
    git_tree = client.tree(project_data["repo"], branch.commit.sha, recursive: true).tree

    project_data["dependency_dirs"].each do |directory|
      selected_paths << select_path_per_directory(git_tree, directory)
    end

    selected_paths.flatten.each do |path|
      path.slice! "/Dockerfile"
      input_files_path << path
    end
  else
    input_files_path = project_data["dependency_dirs"]
  end
end
