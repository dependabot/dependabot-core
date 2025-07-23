# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Helm
    module Helpers
      extend T::Sig

      sig { params(name: String).returns(String) }
      def self.search_releases(name)
        Dependabot.logger.info("Searching Helm repository for: #{name}")

        Dependabot::SharedHelpers.run_shell_command(
          "helm search repo #{name} --versions --output=json",
          fingerprint: "helm search repo <name> --versions --output=json"
        ).strip
      end

      sig { params(repo_name: String, repository_url: String).returns(String) }
      def self.add_repo(repo_name, repository_url)
        Dependabot.logger.info("Adding Helm repository: #{repo_name} (#{repository_url})")

        Dependabot::SharedHelpers.run_shell_command(
          "helm repo add #{repo_name} #{repository_url}",
          fingerprint: "helm repo add <repo_name> <repository_url>"
        )
      end

      sig { returns(String) }
      def self.update_repo
        Dependabot.logger.info("Updating Helm repositories")

        Dependabot::SharedHelpers.run_shell_command(
          "helm repo update",
          fingerprint: "helm repo update"
        )
      end

      sig { returns(String) }
      def self.update_lock
        Dependabot.logger.info("Updating Building Lock File")

        Dependabot::SharedHelpers.run_shell_command(
          "helm dependency update",
          fingerprint: "helm dependency update"
        )
      end

      sig { params(username: String, password: String, repository_url: String).returns(String) }
      def self.registry_login(username, password, repository_url)
        Dependabot.logger.info("Logging into Helm registry \"#{repository_url}\"")

        Dependabot::SharedHelpers.run_shell_command(
          "helm registry login --username #{username} --password #{password} #{repository_url}",
          fingerprint: "helm registry login --username <username> --password <password> <repository_url>"
        )
      rescue StandardError => e
        Dependabot.logger.error(
          "Failed to authenticate for #{repository_url}: #{e.message}"
        )
        raise
      end

      sig { params(username: String, password: String, repository_url: String).returns(String) }
      def self.oci_registry_login(username, password, repository_url)
        Dependabot.logger.info("Logging into OCI registry \"#{repository_url}\"")

        Dependabot::SharedHelpers.run_shell_command(
          "oras login --username #{username} --password #{password} #{repository_url}",
          fingerprint: "oras login --username <username> --password <password> <repository_url>"
        )
      rescue StandardError => e
        Dependabot.logger.error(
          "Failed to authenticate for #{repository_url}: #{e.message}"
        )
        raise
      end

      sig { params(name: String).returns(String) }
      def self.fetch_oci_tags(name)
        Dependabot.logger.info("Searching OCI tags for: #{name}")

        Dependabot::SharedHelpers.run_shell_command(
          "oras repo tags #{name}",
          fingerprint: "oras repo tags <name>"
        ).strip
      end

      sig { params(repo_url: String, tag: String).returns(String) }
      def self.fetch_tags_with_release_date_using_oci(repo_url, tag)
        Dependabot::SharedHelpers.run_shell_command(
          "oras manifest fetch #{repo_url}:#{tag}",
          fingerprint: "oras manifest fetch <repo_url>:<tag>"
        ).strip
      end
    end
  end
end
