# typed: strong
# frozen_string_literal: true

module Dependabot
  module GithubActions
    # Reference to the GitHub.com domain
    GITHUB_COM = T.let("github.com", String)

    # Regular expression to match a GitHub repository reference
    GITHUB_REPO_REFERENCE = T.let(%r{
      ^(?<owner>[\w.-]+)/
      (?<repo>[\w.-]+)
      (?<path>/[^\@]+)?
      @(?<ref>.+)
    }x, Regexp)

    # Matches .yml or .yaml files in the .github/workflows directories
    WORKFLOW_YAML_REGEX = %r{\.github/workflows/.+\.ya?ml$}
    # Matches .yml or .yaml files anywhere
    ALL_YAML_FILES = %r{(?:^|/).+\.ya?ml$}

    # The ecosystem name for GitHub Actions
    ECOSYSTEM = T.let("github_actions", String)

    # The pattern to match manifest files
    MANIFEST_FILE_PATTERN = /\.ya?ml$/
    # The name of the manifest file
    MANIFEST_FILE_YML = T.let("action.yml", String)
    # The name of the manifest file
    MANIFEST_FILE_YAML = T.let("action.yaml", String)
    # The pattern to match any .yml or .yaml file
    ANYTHING_YML = T.let("<anything>.yml", String)
    # The path to the workflow directory
    WORKFLOW_DIRECTORY = T.let(".github/workflows", String)
    # The path to the config .yml file
    CONFIG_YMLS = T.let("#{WORKFLOW_DIRECTORY}/#{ANYTHING_YML}".freeze, String)

    OWNER_KEY = T.let("owner", String)
    REPO_KEY = T.let("repo", String)
    REF_KEY = T.let("ref", String)
    USES_KEY = T.let("uses", String)
    STEPS_KEY = T.let("steps", String)
  end
end
