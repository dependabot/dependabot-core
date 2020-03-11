def recursive_path(feature_package, project_path, dependency_dir, github_token)

  if feature_package == "docker"

    client = Octokit::Client.new(:access_token => github_token)
    branch= client.branch(project_path, "master")
    tree = client.tree(project_path, branch.commit.sha, :recursive => true).tree

    selected_paths = tree.select {|f| f.path.include?("#{dependency_dir}")}.
                      select {|f| f.path.include?("Dockerfile")}.
                      map {|f| f.path}

    input_files_path = []
    selected_paths.each do |path|
        path.slice! "/Dockerfile"
        input_files_path << path
    end
  else
    input_files_path = [dependency_dir]
  end

end
