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
        validate_cli_arg!("repo_name", repo_name)
        validate_cli_arg!("repository_url", repository_url)
        Dependabot.logger.info("Adding Helm repository: #{repo_name} (#{repository_url})")

        Dependabot::SharedHelpers.run_shell_command(
          "helm repo add -- #{repo_name} #{repository_url}",
          fingerprint: "helm repo add -- <repo_name> <repository_url>"
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

      sig { params(name: String).returns(String) }
      def self.fetch_oci_tags(name)
        validate_cli_arg!("name", name)
        Dependabot.logger.info("Searching OCI tags for: #{name}")

        Dependabot::SharedHelpers.run_shell_command(
          "oras repo tags -- #{name}",
          fingerprint: "oras repo tags -- <name>"
        ).strip
      end

      sig { params(repo_url: String, tag: String).returns(String) }
      def self.fetch_tags_with_release_date_using_oci(repo_url, tag)
        validate_cli_arg!("repo_url", repo_url)
        validate_cli_arg!("tag", tag)
        Dependabot::SharedHelpers.run_shell_command(
          "oras manifest fetch -- #{repo_url}:#{tag}",
          fingerprint: "oras manifest fetch -- <repo_url>:<tag>"
        ).strip
      end

      sig { params(argument_name: String, value: String).void }
      def self.validate_cli_arg!(argument_name, value)
        return unless value.match?(/\s/) || value.start_with?("-")

        raise ArgumentError, "Invalid #{argument_name}"
      end
      private_class_method :validate_cli_arg!
    end
  end
end
