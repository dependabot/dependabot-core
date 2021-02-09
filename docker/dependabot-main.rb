# frozen_string_literal: true

require "dependabot/docker"
require "dependabot/auto_merge"
require "dependabot/pr_info"
require "dependabot/path_level"
require "yaml"

def create_pr(source, commit, updated_deps, updated_files, credentials_github)
  # Create a pull request for the update
  pr = Dependabot::PullRequestCreator.new(
    source: source,
    base_commit: commit,
    dependencies: updated_deps,
    files: updated_files,
    credentials: credentials_github,
    label_language: true,
    branch_name_prefix: nil,
    branch_name_separator: "-",
    pr_message_footer: pr_info(updated_deps.first)
  )
  pr.create
end

def requirements(checker)
  requirements =
    if !checker.requirements_unlocked_or_can_be?
      if checker.can_update?(requirements_to_unlock: :none) then :none
      else :update_not_possible
      end
    elsif checker.can_update?(requirements_to_unlock: :own) then :own
    elsif checker.can_update?(requirements_to_unlock: :all) then :all
    else :update_not_possible
    end
  requirements
end

def fetch_files_and_commit(source, credentials_github)
  # Fetch the dependency files
  fetcher = Dependabot::FileFetchers.for_package_manager("docker").
            new(source: source, credentials: credentials_github)

  files = fetcher.files
  commit = fetcher.commit

  [files, commit]
end

def fetch_dependencies(files, source)
  # Parse the dependency files
  parser = Dependabot::FileParsers.for_package_manager("docker").new(
    dependency_files: files, source: source
  )
  parser.parse
end

def update_files(dep, updated_deps, files)
  # Generate updated dependency files
  print "  - Updating #{dep.name} (from #{dep.version}) \n"
  updater = Dependabot::FileUpdaters.for_package_manager("docker").new(
    dependencies: updated_deps, dependency_files: files, credentials: nil
  )
  updater.updated_dependency_files
end

def checker_init(dep, files, docker_cred)
  # Get update details for the dependency
  Dependabot::UpdateCheckers.for_package_manager("docker").new(
    dependency: dep, dependency_files: files, credentials: [docker_cred]
  )
end

def source_init(file_path, project_data)
  Dependabot::Source.new(
    provider: "github", repo: project_data["repo"],
    directory: file_path, branch: project_data["branch"]
  )
end

def checker_up_to_date(checker)
  checker.up_to_date?
end

def checker_updated_dependencies(checker, requirements_to_unlock)
  checker.updated_dependencies(
    requirements_to_unlock: requirements_to_unlock
  )
end

def main(project_data, github_token, docker_cred)
  credentials_github = [{
    "type" => "git_source",
    "host" => "github.com",
    "username" => "dependabot-script",
    "password" => github_token
  }]

  input_files_path = recursive_path(project_data, github_token)

  input_files_path.each do |file_path|
    print "  - Checking the files in #{file_path}\n"
    source = source_init(file_path, project_data)
    files, commit = fetch_files_and_commit(source, credentials_github)
    dependencies = fetch_dependencies(files, source)

    dependencies.select(&:top_level?).each do |dep|
      checker = checker_init(dep, files, docker_cred)
      next if checker_up_to_date(checker)

      requirements_to_unlock = requirements(checker)
      next if requirements_to_unlock == :update_not_possible

      updated_deps = checker_updated_dependencies(checker, requirements_to_unlock)
      next if updated_deps.first.version == updated_deps.first.previous_version

      updated_files = update_files(dep, updated_deps, files)
      pull_request = create_pr(source, commit, updated_deps, updated_files, credentials_github)
      next unless pull_request

      puts pull_request[:html_url]
      next unless project_data["module"] == "docker"

      auto_merge(pull_request[:number], pull_request[:head][:ref], project_data["repo"], github_token)
    end
  end
  "Success"
end

# LIST OF ENVIROMENTAL VARIABLES NEEDED:
# REPOSITORY_DATA list of dictionaries. Each dictionary should contain the following keys:
#   - repo i.e. Pix4D/test-dependabot-docker
#   - module i.e docker or concourse
#   - dependency_dir i.e. ci/docker or ci/pipelines
#   - branch i.e master
# GITHUB_ACCESS_TOKEN
# DOCKER_REGISTRY i.e. docker.ci.pix4d.com
# DOCKER_USER
# DOCKER_PASS

# PROGRAM ENTRY POINT
if __FILE__ == $PROGRAM_NAME
  docker_cred = {
    "type" => "docker_registry",
    "registry" => (ENV["DOCKER_REGISTRY"] || "registry.hub.docker.com"),
    "username" => (ENV["DOCKER_USER"] || nil),
    "password" => (ENV["DOCKER_PASS"] || nil)
  }

  github_token = ENV["GITHUB_ACCESS_TOKEN"]

  ENV["REPOSITORY_DATA"] || raise("Environmental variable REPOSITORY_DATA is not set")

  input_data = YAML.safe_load(ENV["REPOSITORY_DATA"], [], [], true)

  unless input_data.is_a?(Array) && !input_data.empty?
    raise TypeError,
          "REPOSITORY_DATA should be a non-empty list of dictonaries"
  end

  input_data.each do |project_data|
    raise KeyError, "REPOSITORY_DATA items should not be empty" if project_data.keys.empty?

    missing_keys = %w(module repo branch dependency_dir) - project_data.keys
    raise KeyError, "Each REPOSITORY_DATA item should contain 4 non empty keys" unless missing_keys.empty?

    main(project_data, github_token, docker_cred)
  end
end
