# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/github_actions/version"
require "dependabot/ecosystem"
require "dependabot/github_actions/requirement"

module Dependabot
  module GithubActions
    DOTCOM = "github.com"

    GITHUB_REPO_REFERENCE = %r{
      ^(?<owner>[\w.-]+)/
      (?<repo>[\w.-]+)
      (?<path>/[^\@]+)?
      @(?<ref>.+)
    }x

    # Matches .yml or .yaml files in the .github/workflows directories
    WORKFLOW_YAML_REGEX = %r{\.github/workflows/.+\.ya?ml$}
    ALL_YAML_FILES = %r{(?:^|/).+\.ya?ml$}

    ECOSYSTEM = T.let("github_actions", String)
    PACKAGE_MANAGER = T.let("github_actions", String)

    NO_DEPENDENCY_NAME = "unknown"
    NO_VERSION = "0.0.0"
    MANIFEST_FILE_PATTERN = /\.ya?ml$/
    MANIFEST_FILE_YML = T.let("action.yml", String)
    MANIFEST_FILE_YAML = T.let("action.yaml", String)
    ANYTHING_YML = T.let("<anything>.yml", String)
    ANYTHING_YAML = T.let("<anything>.yaml", String)
    WORKFLOW_DIRECTORY = T.let(".github/workflows", String)
    CONFIG_YMLS = T.let("#{WORKFLOW_DIRECTORY}/#{ANYTHING_YML}".freeze, String)
    CONFIG_YAMLS = T.let("#{WORKFLOW_DIRECTORY}/#{ANYTHING_YAML}".freeze, String)

    JOBS_KEY = T.let("jobs", String)
    RUNS_KEY = T.let("runs", String)
    OWNER_KEY = T.let("owner", String)
    REPO_KEY = T.let("repo", String)
    REF_KEY = T.let("ref", String)
    USES_KEY = T.let("uses", String)
    STEPS_KEY = T.let("steps", String)

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig do
        params(
          use_name: String,
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(use_name, raw_version, requirement = nil)
        @use_name = use_name
        super(
          PACKAGE_MANAGER,
          Version.new(raw_version),
          [],
          [],
          requirement,
       )
      end

      sig { returns(String) }
      attr_reader :use_name

      sig { override.returns(String) }
      def version_to_s
        "#{use_name}@#{version}"
      end

      sig { override.returns(String) }
      def version_to_raw_s
        "#{use_name}@#{version.to_semver}"
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        false
      end
    end
  end
end
