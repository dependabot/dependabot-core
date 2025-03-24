# typed: strict
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

      sig { params(repo_name: String, repo_url: String).returns(String) }
      def self.add_repo(repo_name, repo_url)
        Dependabot.logger.info("Adding Helm repository: #{repo_name} (#{repo_url})")

        Dependabot::SharedHelpers.run_shell_command(
          "helm repo add #{repo_name} #{repo_url}",
          fingerprint: "helm repo add <repo_name> <repo_url>"
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
    end
  end
end
