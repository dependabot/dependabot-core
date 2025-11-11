# typed: strict
# frozen_string_literal: true

require "json"
require "base64"
require "sorbet-runtime"
require "dependabot/shared_helpers"
require "dependabot/clients/github_with_retries"
require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/bazel/update_checker"

module Dependabot
  module Bazel
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class RegistryClient
        extend T::Sig

        GITHUB_REPO = T.let("bazelbuild/bazel-central-registry", String)
        RAW_BASE = T.let("https://raw.githubusercontent.com/#{GITHUB_REPO}/main".freeze, String)

        sig { params(credentials: T::Array[Dependabot::Credential]).void }
        def initialize(credentials:)
          @credentials = credentials
        end

        sig { params(module_name: String).returns(T::Array[String]) }
        def all_module_versions(module_name)
          contents = T.unsafe(github_client).contents(GITHUB_REPO, path: "modules/#{module_name}")
          return [] unless contents.is_a?(Array)

          versions = contents.filter_map do |item|
            next unless item[:type] == "dir"

            item[:name]
          end

          versions.sort_by { |v| version_sort_key(v) }
        rescue Octokit::NotFound
          Dependabot.logger.info("Module '#{module_name}' not found in registry")
          []
        end

        sig { params(module_name: String).returns(T.nilable(String)) }
        def latest_module_version(module_name)
          versions = all_module_versions(module_name)
          return nil if versions.empty?

          versions.max_by { |v| version_sort_key(v) }
        end

        sig { params(module_name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
        def get_metadata(module_name)
          versions = all_module_versions(module_name)
          return nil if versions.empty?

          {
            "name" => module_name,
            "versions" => versions,
            "latest_version" => latest_module_version(module_name)
          }
        end

        sig { params(module_name: String, version: String).returns(T.nilable(T::Hash[String, T.untyped])) }
        def get_source(module_name, version)
          file_path = "modules/#{module_name}/#{version}/source.json"

          begin
            content = T.unsafe(github_client).contents(GITHUB_REPO, path: file_path)
            return nil unless content

            decoded_content = Base64.decode64(content.content)
            JSON.parse(decoded_content)
          rescue StandardError => e
            Dependabot.logger.warn("Failed to get source for #{module_name}@#{version}: #{e.message}")
            nil
          end
        end

        sig { params(module_name: String, version: String).returns(T.nilable(String)) }
        def get_module_bazel(module_name, version)
          file_path = "modules/#{module_name}/#{version}/MODULE.bazel"

          begin
            content = T.unsafe(github_client).contents(GITHUB_REPO, path: file_path)
            return nil unless content

            Base64.decode64(content.content)
          rescue StandardError => e
            Dependabot.logger.warn("Failed to get MODULE.bazel for #{module_name}@#{version}: #{e.message}")
            nil
          end
        end

        sig { params(module_name: String, version: String).returns(T::Boolean) }
        def module_version_exists?(module_name, version)
          !get_source(module_name, version).nil?
        end

        sig { params(module_name: String, version: String).returns(T.nilable(Time)) }
        def get_version_release_date(module_name, version)
          file_path = "modules/#{module_name}/#{version}/MODULE.bazel"

          commits = begin
            T.unsafe(github_client).commits("bazelbuild/bazel-central-registry", path: file_path, per_page: 1)
          rescue StandardError => e
            Dependabot.logger.warn("Failed to get release date for #{module_name} #{version}: #{e.message}")
          end

          return nil unless commits&.any?

          commits.first.commit.committer.date
        end

        private

        sig { returns(Dependabot::Clients::GithubWithRetries) }
        def github_client
          @github_client ||= T.let(
            Dependabot::Clients::GithubWithRetries.for_github_dot_com(credentials: @credentials),
            T.nilable(Dependabot::Clients::GithubWithRetries)
          )
        end

        sig { params(version: String).returns(T::Array[Integer]) }
        def version_sort_key(version)
          cleaned = version.gsub(/^v/, "")
          parts = cleaned.split(".")
          parts.map { |part| part.match?(/^\d+$/) ? part.to_i : 0 }
        end
      end
    end
  end
end
