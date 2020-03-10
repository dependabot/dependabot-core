# LIST OF ENVIROMENTAL VARIABLES NEEDED:
  # FEATURE_PACKAGE i.e docker or concourse
  # PROJECT_PATH i.e. Pix4D/test-dependabot-docker
  # DEPENDENCY_DIRECTORY i.e. ci/docker or ci/pipelines
  # REPOSITORY_BRANCH default is master
  # GITHUB_ACCESS_TOKEN
  # DOCKER_REGISTRY i.e. docker.ci.pix4d.com
  # DOCKER_USER
  # DOCKER_PASS

require "dependabot/docker"
require "dependabot/pr_info"
require "dependabot/path_level.rb"

credentials_github =
  [{
    "type" => "git_source",
    "host" => "github.com",
    "username" => "dependabot-script",
    "password" => ENV["GITHUB_ACCESS_TOKEN"]
  }]

credentials_docker =
  [{
    "type" => "docker_registry",
    "registry" => (ENV["DOCKER_REGISTRY"]  || "registry.hub.docker.com"),
    "username" => (ENV["DOCKER_USER"] || nil),
    "password" => (ENV["DOCKER_PASS"] || nil)
  }]

input_files_path = recursive_path(
  ENV["FEATURE_PACKAGE"],
  ENV["PROJECT_PATH"],
  ENV["DEPENDENCY_DIRECTORY"],
  ENV["GITHUB_ACCESS_TOKEN"]
)

input_files_path.each do |file_path|

  #
  # Source setup
  #
  print "  - Checking the file in #{file_path}\n"
  source = Dependabot::Source.new(
    provider: "github",
    repo: ENV["PROJECT_PATH"],
    directory: file_path,
    branch: (ENV["REPOSITORY_BRANCH"] || nil)
  )

  #
  # Fetch the dependency files
  #
  fetcher = Dependabot::FileFetchers.for_package_manager("docker").
            new(source: source, credentials: credentials_github)

  files = fetcher.files
  commit = fetcher.commit

  #
  # Parse the dependency files
  #
  parser = Dependabot::FileParsers.for_package_manager("docker").new(
    dependency_files: files,
    source: source
  )
  dependencies = parser.parse

  dependencies.select(&:top_level?).each do |dep|
    #
    # Get update details for the dependency
    #
    checker = Dependabot::UpdateCheckers.for_package_manager("docker").new(
      dependency: dep,
      dependency_files: files,
      credentials: credentials_docker,
    )
    next if checker.up_to_date?

    requirements_to_unlock =
      if !checker.requirements_unlocked_or_can_be?
        if checker.can_update?(requirements_to_unlock: :none) then :none
        else :update_not_possible
        end
      elsif checker.can_update?(requirements_to_unlock: :own) then :own
      elsif checker.can_update?(requirements_to_unlock: :all) then :all
      else :update_not_possible
      end

    next if requirements_to_unlock == :update_not_possible

    updated_deps = checker.updated_dependencies(
      requirements_to_unlock: requirements_to_unlock
    )

    next if updated_deps.first.version == updated_deps.first.previous_version
    #
    # Generate updated dependency files
    #
    print "  - Updating #{dep.name} (from #{dep.version}) \n"
    updater = Dependabot::FileUpdaters.for_package_manager("docker").new(
      dependencies: updated_deps,
      dependency_files: files,
      credentials: nil
    )
    updated_files = updater.updated_dependency_files

    #
    # Create a pull request for the update
    #
    pr_creator = Dependabot::PullRequestCreator.new(
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

    pull_request = pr_creator.create
    puts " submitted"

    next unless pull_request
  end
end
puts "Done"
