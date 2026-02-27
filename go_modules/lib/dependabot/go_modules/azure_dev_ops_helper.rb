# typed: strict
# frozen_string_literal: true

require "shellwords"
require "sorbet-runtime"
require "uri"

require "dependabot/shared_helpers"

module Dependabot
  module GoModules
    # Configures git URL rewriting and GOPRIVATE for Azure DevOps Go modules.
    #
    # Azure DevOps requires /_git/ in the URL path, but Go module paths omit it:
    #   Module path: dev.azure.com/{org}/{project}/{repo}.git
    #   Git URL:     https://dev.azure.com/{org}/{project}/_git/{repo}
    #
    # Go strips .git and passes the bare path to git, so we register insteadOf
    # rules for all URL forms git may encounter (bare, .git suffix, trailing /).
    #
    # Repo names containing dots are excluded to avoid ambiguity with .git.
    module AzureDevOpsHelper
      extend T::Sig

      AZURE_DEVOPS_HOST = T.let("dev.azure.com", String)

      # Keep in sync with go_modules/helpers/importresolver/main.go
      # (azureDevOpsPattern). This pattern matches bare module paths (no scheme);
      # the Go pattern matches full https:// URLs.
      AZURE_DEVOPS_MODULE_PATTERN = T.let(
        %r{
          ^dev\.azure\.com/
          (?<org>[a-zA-Z0-9_.-]+)/
          (?<project>[a-zA-Z0-9_.-]+)/
          (?<repo>[a-zA-Z0-9_-]+)
          (?:\.git)?(?:/|$)
        }x,
        Regexp
      )

      sig { params(module_path: String).void }
      def self.configure_go_for_azure_devops(module_path)
        configure_git_url_for_azure_devops(module_path)
        configure_goprivate_for_azure_devops(module_path)
      end

      sig { params(module_path: String).void }
      def self.configure_git_url_for_azure_devops(module_path)
        match = module_path.match(AZURE_DEVOPS_MODULE_PATTERN)
        return unless match

        org = T.must(match[:org])
        project = T.must(match[:project])
        repo = T.must(match[:repo])

        azure_git_url_raw = "https://dev.azure.com/#{org}/#{project}/_git/#{repo}"
        flat_url_raw = "https://dev.azure.com/#{org}/#{project}/#{repo}"

        # Verify constructed URLs resolve to the expected host to prevent
        # request forgery via crafted module paths.
        return unless [azure_git_url_raw, flat_url_raw].all? do |u|
          URI.parse(u).host == AZURE_DEVOPS_HOST
        end

        azure_git_url = Shellwords.escape(azure_git_url_raw)
        flat_url = Shellwords.escape(flat_url_raw)

        # --replace-all with a BRE value pattern so each rule replaces only its
        # own entry without clobbering siblings under the same key.
        base = Regexp.escape("https://dev.azure.com/#{org}/#{project}/#{repo}")
        SharedHelpers.run_shell_command(
          "git config --global --replace-all url.#{azure_git_url}.insteadOf #{flat_url} #{base}$"
        )
        SharedHelpers.run_shell_command(
          "git config --global --replace-all url.#{azure_git_url}.insteadOf #{flat_url}.git #{base}\\.git$"
        )
        SharedHelpers.run_shell_command(
          "git config --global --replace-all url.#{azure_git_url}/.insteadOf #{flat_url}/ #{base}/$"
        )
      end

      # proxy.golang.org does not serve Azure DevOps packages, so GOPRIVATE must
      # include dev.azure.com for direct VCS access (where our insteadOf rules
      # apply). Scoped to the whole domain since Azure DevOps modules are almost
      # always private. Mutates ENV for the process lifetime; safe because Go
      # commands run in ephemeral containers.
      sig { params(module_path: String).void }
      def self.configure_goprivate_for_azure_devops(module_path)
        return unless module_path.start_with?("dev.azure.com/")

        current = ENV.fetch("GOPRIVATE", "")
        entries = current.split(",").map(&:strip)
        return if entries.include?("*") || entries.include?("dev.azure.com")

        ENV["GOPRIVATE"] = (entries + ["dev.azure.com"]).reject(&:empty?).join(",")
      end

      private_class_method :configure_git_url_for_azure_devops, :configure_goprivate_for_azure_devops
    end
  end
end
