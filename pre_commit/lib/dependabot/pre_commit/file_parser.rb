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
require "dependabot/npm_and_yarn/requirement"
require "dependabot/python/requirement_parser"
require "dependabot/bundler/requirement"

module Dependabot
  module PreCommit
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      CONFIG_FILE_PATTERN = /\.pre-commit(-config)?\.ya?ml$/i
      ECOSYSTEM = "pre_commit"

      LANGUAGE_PARSERS = T.let(
        {
          "python" => ->(dep_string) { Dependabot::Python::RequirementParser.parse(dep_string) },
          "node" => ->(dep_string) { Dependabot::NpmAndYarn::Requirement.parse_dep_string(dep_string) },
          "ruby" => ->(dep_string) { Dependabot::Bundler::Requirement.parse_dep_string(dep_string) }
        }.freeze,
        T::Hash[String, T.proc.params(dep_string: String).returns(T.nilable(T::Hash[Symbol, T.untyped]))]
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
          repo: T::Hash[String, T.untyped],
          file: Dependabot::DependencyFile
        ).returns(T.nilable(Dependency))
      end
      def parse_repo(repo, file)
        repo_url = repo["repo"]
        rev = repo["rev"]

        return nil if repo_url.nil? || rev.nil?
        return nil if %w(local meta).include?(repo_url)

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
            }
          }],
          package_manager: ECOSYSTEM
        )
      end

      sig do
        params(
          repo: T::Hash[String, T.untyped],
          file: Dependabot::DependencyFile
        ).returns(T::Array[Dependabot::Dependency])
      end
      def parse_additional_dependencies(repo, file)
        dependencies = []
        repo_url = repo["repo"]

        return dependencies if repo_url.nil? || %w(local meta).include?(repo_url)

        hooks = repo.fetch("hooks", [])
        hooks.each do |hook|
          next unless hook.is_a?(Hash)

          hook_deps = parse_hook_additional_dependencies(hook, repo_url, file)
          dependencies.concat(hook_deps)
        end

        dependencies
      end

      sig do
        params(
          hook: T::Hash[String, T.untyped],
          repo_url: String,
          file: Dependabot::DependencyFile
        ).returns(T::Array[Dependabot::Dependency])
      end
      def parse_hook_additional_dependencies(hook, repo_url, file)
        dependencies = []

        return dependencies unless hook["id"]

        additional_deps = hook.fetch("additional_dependencies", [])
        return dependencies if additional_deps.empty?

        parser = LANGUAGE_PARSERS[hook["language"]]
        return dependencies unless parser

        additional_deps.each do |dep_string|
          next unless dep_string.is_a?(String)

          parsed = parser.call(dep_string)
          next unless parsed

          dependencies << Dependabot::Dependency.new(
            name: parsed[:normalised_name],
            version: parsed[:version],
            requirements: [{
              requirement: parsed[:requirement],
              groups: ["additional_dependencies"],
              file: file.name,
              source: {
                type: "additional_dependency",
                language: hook["language"],
                package_name: parsed[:normalised_name],
                original_name: parsed[:name],
                hook_id: hook["id"],
                hook_repo: repo_url,
                extras: parsed[:extras],
                original_string: dep_string
              }
            }],
            package_manager: ECOSYSTEM
          )
        end

        dependencies
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
