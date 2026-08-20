# typed: strict
# frozen_string_literal: true

require "yaml"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/errors"
require "dependabot/pre_commit/package_manager"
require "dependabot/pre_commit/version"
require "dependabot/pre_commit/requirement"
require "dependabot/cargo/requirement"
require "dependabot/npm_and_yarn/requirement"
require "dependabot/pub/requirement"
require "dependabot/python/requirement_parser"
require "dependabot/bundler/requirement"
require "dependabot/go_modules/requirement_parser"

module Dependabot
  module PreCommit
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"
      require_relative "file_parser/hook_language_fetcher"

      CONFIG_FILE_PATTERN = /\.pre-commit(-config)?\.ya?ml$/i
      ECOSYSTEM = "pre_commit"

      LANGUAGE_PARSERS = T.let(
        {
          "python" => ->(dep_string) { Dependabot::Python::RequirementParser.parse(dep_string) },
          "node" => ->(dep_string) { Dependabot::NpmAndYarn::Requirement.parse_dep_string(dep_string) },
          "rust" => ->(dep_string) { Dependabot::Cargo::Requirement.parse_dep_string(dep_string) },
          "golang" => ->(dep_string) { Dependabot::GoModules::RequirementParser.parse(dep_string) },
          "ruby" => ->(dep_string) { Dependabot::Bundler::Requirement.parse_dep_string(dep_string) },
          "dart" => ->(dep_string) { Dependabot::Pub::Requirement.parse_dep_string(dep_string) }
        }.freeze,
        T::Hash[String, T.proc.params(dep_string: String).returns(T.nilable(T::Hash[Symbol, Object]))]
      )

      sig { override.returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          ),
          T.nilable(Ecosystem)
        )
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        pre_commit_config_files.each do |file|
          dependency_set += parse_config_file(file)
        end

        dependency_set.dependencies
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(PackageManager.new, T.nilable(Dependabot::PreCommit::PackageManager))
      end

      sig { params(file: Dependabot::DependencyFile).returns(DependencySet) }
      def parse_config_file(file)
        dependency_set = DependencySet.new

        yaml = YAML.safe_load(T.must(file.content), aliases: true)
        return dependency_set unless yaml.is_a?(Hash)

        repos = yaml.fetch("repos", [])
        return dependency_set unless repos.is_a?(Array)

        repos.each do |repo|
          next unless repo.is_a?(Hash)

          dependency = parse_repo(repo, file)
          dependency_set << dependency if dependency

          additional_deps = parse_additional_dependencies(repo, file)
          additional_deps.each { |dep| dependency_set << dep }
        end

        dependency_set
      rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias => e
        raise Dependabot::DependencyFileNotParseable.new(file.path, e.message)
      end

      sig do
        params(
          repo: T::Hash[String, Object],
          file: Dependabot::DependencyFile
        ).returns(T.nilable(Dependency))
      end
      def parse_repo(repo, file)
        repo_url = repo["repo"]
        rev = repo["rev"]

        return nil unless repo_url.is_a?(String) && rev.is_a?(String)
        return nil if %w(local meta).include?(repo_url)

        comment = rev_line_comment(file, repo_url)

        Dependency.new(
          name: repo_url,
          version: rev,
          requirements: [{
            requirement: nil,
            groups: [],
            file: file.name,
            source: {
              type: "git",
              url: repo_url,
              ref: rev,
              branch: nil
            },
            metadata: { comment: comment }
          }],
          package_manager: ECOSYSTEM
        )
      end

      sig do
        params(
          repo: T::Hash[String, Object],
          file: Dependabot::DependencyFile
        ).returns(T::Array[Dependabot::Dependency])
      end
      def parse_additional_dependencies(repo, file)
        dependencies = []
        repo_url = repo["repo"]
        revision = repo["rev"]

        return dependencies unless repo_url.is_a?(String)
        return dependencies if %w(local meta).include?(repo_url)

        revision = nil unless revision.is_a?(String)

        hooks = repo.fetch("hooks", [])
        return dependencies unless hooks.is_a?(Array)

        hooks.each do |hook|
          next unless hook.is_a?(Hash)

          hook_deps = parse_hook_additional_dependencies(hook, repo_url, revision, file)
          dependencies.concat(hook_deps)
        end

        dependencies
      end

      sig do
        params(
          hook: T::Hash[String, Object],
          repo_url: String,
          revision: T.nilable(String),
          file: Dependabot::DependencyFile
        ).returns(T::Array[Dependabot::Dependency])
      end
      def parse_hook_additional_dependencies(hook, repo_url, revision, file)
        dependencies = []
        hook_id = hook["id"]

        return dependencies unless hook_id.is_a?(String)

        additional_deps = hook.fetch("additional_dependencies", [])
        return dependencies unless additional_deps.is_a?(Array)
        return dependencies if additional_deps.empty?

        # Get language from local config first, then try fetching from hook source repo
        language = resolve_hook_language(hook, repo_url, revision, hook_id)
        return dependencies unless language

        parser = LANGUAGE_PARSERS[language]
        return dependencies unless parser

        additional_deps.each do |dep_string|
          next unless dep_string.is_a?(String)

          parsed = parser.call(dep_string)
          source_details = { language: language, hook_id: hook_id, repo_url: repo_url }
          dependency = parsed && build_additional_dependency(parsed, dep_string, source_details, file)
          dependencies << dependency if dependency
        end

        dependencies
      end

      sig do
        params(
          parsed: T::Hash[Symbol, Object],
          dep_string: String,
          source_details: T::Hash[Symbol, String],
          file: Dependabot::DependencyFile
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def build_additional_dependency(parsed, dep_string, source_details, file)
        normalised_name = parsed[:normalised_name]
        return unless normalised_name.is_a?(String)

        version = parsed[:version]
        return unless version.nil? || version.is_a?(String) || version.is_a?(Dependabot::Version)

        Dependabot::Dependency.new(
          name: normalised_name,
          version: version,
          requirements: [additional_dependency_requirement(parsed, dep_string, source_details, file)],
          package_manager: ECOSYSTEM
        )
      end

      sig do
        params(
          parsed: T::Hash[Symbol, Object],
          dep_string: String,
          source_details: T::Hash[Symbol, String],
          file: Dependabot::DependencyFile
        ).returns(T::Hash[Symbol, Object])
      end
      def additional_dependency_requirement(parsed, dep_string, source_details, file)
        {
          requirement: parsed[:requirement],
          groups: ["additional_dependencies"],
          file: file.name,
          source: {
            type: "additional_dependency",
            language: source_details.fetch(:language),
            package_name: parsed[:normalised_name],
            original_name: parsed[:name],
            hook_id: source_details.fetch(:hook_id),
            hook_repo: source_details.fetch(:repo_url),
            extras: parsed[:extras],
            original_string: dep_string
          }
        }
      end

      sig do
        params(
          hook: T::Hash[String, Object],
          repo_url: String,
          revision: T.nilable(String),
          hook_id: String
        ).returns(T.nilable(String))
      end
      def resolve_hook_language(hook, repo_url, revision, hook_id)
        # Use local language if explicitly specified
        local_language = hook["language"]
        return local_language if local_language.is_a?(String)

        # Otherwise fetch from the hook source repository
        return nil unless revision

        hook_language_fetcher.fetch_language(
          repo_url: repo_url,
          revision: revision,
          hook_id: hook_id
        )
      end

      sig { returns(HookLanguageFetcher) }
      def hook_language_fetcher
        @hook_language_fetcher ||= T.let(
          HookLanguageFetcher.new(credentials: credentials),
          T.nilable(HookLanguageFetcher)
        )
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          repo_url: String
        ).returns(T.nilable(String))
      end
      def rev_line_comment(file, repo_url)
        current_repo = T.let(nil, T.nilable(String))

        T.must(file.content).each_line do |line|
          repo_match = line.match(/^\s*-\s*repo:\s*["']?([^"'\s]+)["']?/)
          current_repo = repo_match[1] if repo_match

          next unless current_repo == repo_url

          rev_match = line.match(/^\s*rev:\s*\S+\s*(#.*)$/)
          return T.must(rev_match[1]).rstrip if rev_match
        end

        nil
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pre_commit_config_files
        dependency_files.select { |f| f.name.match?(CONFIG_FILE_PATTERN) }
      end

      sig { override.void }
      def check_required_files
        return if pre_commit_config_files.any?

        raise "No pre-commit configuration file found!"
      end
    end
  end
end

Dependabot::FileParsers.register("pre_commit", Dependabot::PreCommit::FileParser)
