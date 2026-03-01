# typed: strict
# frozen_string_literal: true

require "yaml"
require "base64"
require "sorbet-runtime"
require "dependabot/clients/github_with_retries"
require "dependabot/shared_helpers"
require "dependabot/source"

require "dependabot/pre_commit/file_parser"

module Dependabot
  module PreCommit
    class FileParser < Dependabot::FileParsers::Base
      # Fetches hook language information from the source repository's
      # .pre-commit-hooks.yaml file. This is needed because the language field
      # is typically defined in the hook repo, not in the consumer's
      # .pre-commit-config.yaml file.
      class HookLanguageFetcher
        extend T::Sig

        HOOKS_FILE = ".pre-commit-hooks.yaml"

        sig do
          params(
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(credentials:)
          @credentials = credentials
          @hooks_cache = T.let({}, T::Hash[String, T.nilable(T::Array[T::Hash[String, T.untyped]])])
        end

        # Fetches the language for a specific hook from the hook source repository.
        #
        # @param repo_url [String] The URL of the hook repository (e.g., "https://github.com/psf/black")
        # @param revision [String] The revision (tag, SHA, branch) to fetch from
        # @param hook_id [String] The hook ID to look up (e.g., "black")
        # @return [String, nil] The language for the hook, or nil if not found
        sig do
          params(
            repo_url: String,
            revision: String,
            hook_id: String
          ).returns(T.nilable(String))
        end
        def fetch_language(repo_url:, revision:, hook_id:)
          hooks = fetch_hooks_from_repo(repo_url, revision)
          return nil unless hooks

          hook = hooks.find { |h| h["id"] == hook_id }
          return nil unless hook

          T.cast(hook["language"], T.nilable(String))
        end

        private

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig do
          params(
            repo_url: String,
            revision: String
          ).returns(T.nilable(T::Array[T::Hash[String, T.untyped]]))
        end
        def fetch_hooks_from_repo(repo_url, revision)
          cache_key = "#{repo_url}@#{revision}"
          return @hooks_cache[cache_key] if @hooks_cache.key?(cache_key)

          hooks = fetch_hooks_internal(repo_url, revision)
          @hooks_cache[cache_key] = hooks
          hooks
        end

        sig do
          params(
            repo_url: String,
            revision: String
          ).returns(T.nilable(T::Array[T::Hash[String, T.untyped]]))
        end
        def fetch_hooks_internal(repo_url, revision)
          source = Source.from_url(repo_url)
          return fetch_via_git_clone(repo_url, revision) unless source
          return fetch_via_git_clone(repo_url, revision) unless source.provider == "github"

          fetch_from_github(source, revision)
        rescue StandardError => e
          Dependabot.logger.debug("Failed to fetch hooks from #{repo_url}@#{revision}: #{e.message}")
          nil
        end

        sig do
          params(
            source: Dependabot::Source,
            revision: String
          ).returns(T.nilable(T::Array[T::Hash[String, T.untyped]]))
        end
        def fetch_from_github(source, revision)
          response = github_client.send(
            :contents,
            source.repo,
            path: HOOKS_FILE,
            ref: revision
          )
          return nil unless response

          content = Base64.decode64(response.content)
          parse_hooks_yaml(content)
        rescue Octokit::NotFound
          Dependabot.logger.debug("#{HOOKS_FILE} not found in #{source.repo}@#{revision}")
          nil
        rescue StandardError => e
          Dependabot.logger.debug("Error fetching from GitHub: #{e.message}")
          fetch_via_git_clone("https://github.com/#{source.repo}", revision)
        end

        sig do
          params(
            repo_url: String,
            revision: String
          ).returns(T.nilable(T::Array[T::Hash[String, T.untyped]]))
        end
        def fetch_via_git_clone(repo_url, revision)
          source = Source.from_url(repo_url)
          return nil unless source

          SharedHelpers.in_a_temporary_directory(File.dirname(source.repo)) do |temp_dir|
            repo_contents_path = File.join(temp_dir, File.basename(source.repo))

            SharedHelpers.run_shell_command(
              "git clone --no-checkout --depth 1 #{repo_url} #{repo_contents_path}",
              fingerprint: "git clone --no-checkout --depth 1 <url> <path>"
            )

            Dir.chdir(repo_contents_path) do
              # Fetch the specific revision and checkout the hooks file
              SharedHelpers.run_shell_command(
                "git fetch --depth 1 origin #{revision}",
                fingerprint: "git fetch --depth 1 origin <revision>"
              )
              SharedHelpers.run_shell_command(
                "git checkout FETCH_HEAD -- #{HOOKS_FILE}",
                fingerprint: "git checkout FETCH_HEAD -- <file>"
              )

              return nil unless File.exist?(HOOKS_FILE)

              content = File.read(HOOKS_FILE)
              parse_hooks_yaml(content)
            end
          end
        rescue StandardError => e
          Dependabot.logger.debug("Failed to clone and fetch hooks: #{e.message}")
          nil
        end

        sig { params(content: String).returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
        def parse_hooks_yaml(content)
          yaml = YAML.safe_load(content, aliases: true)
          return nil unless yaml.is_a?(Array)

          yaml.grep(Hash)
        rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias => e
          Dependabot.logger.debug("Failed to parse hooks YAML: #{e.message}")
          nil
        end

        sig { returns(Dependabot::Clients::GithubWithRetries) }
        def github_client
          @github_client ||= T.let(
            Dependabot::Clients::GithubWithRetries.for_github_dot_com(credentials: credentials),
            T.nilable(Dependabot::Clients::GithubWithRetries)
          )
        end
      end
    end
  end
end
