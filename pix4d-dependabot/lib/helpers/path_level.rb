# frozen_string_literal: true

def select_path_per_directory(git_tree, directory)
  files = git_tree.select do |f|
    f.path.include?(directory.delete_prefix("/").to_s) && f.path.include?("Dockerfile")
  end

  files.map { |item| item["path"] }
end

def normalize_path(path)
  return path if path == "/"

  path = path.delete_suffix("/")
  return path if path.start_with?("/")

  path.prepend("/")
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
    input_files_path = []
    # normalize the path first because pip module fails if there is no '/'
    # at the beginning of dependency_dirs paths ["/path_1/", "/path_2"]`
    project_data["dependency_dirs"].each do |path|
      input_files_path << normalize_path(path)
    end
    raise StandardError unless project_data["dependency_dirs"].length == input_files_path.length

    input_files_path
  end
end
