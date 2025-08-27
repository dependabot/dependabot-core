# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/logger"
require "dependabot/shared_helpers"
require "dependabot/go_modules/vanity_import_resolver"

module Dependabot
  module GoModules
    module UpdaterHelper
      extend T::Sig

      # Configure git rewrite rules for vanity import hosts
      # This prevents SSH URL failures when Go toolchain discovers git hosts from vanity imports
      sig { params(dependencies: T::Array[Dependabot::Dependency], credentials: T::Array[Dependabot::Credential]).void }
      def self.configure_git_vanity_imports(dependencies, credentials)
        return unless dependencies.any?

        resolver = Dependabot::GoModules::VanityImportResolver.new(
          dependencies: dependencies,
          credentials: credentials
        )
        return unless resolver.vanity_imports?

        begin
          git_hosts = resolver.resolve_git_hosts

          if git_hosts.any?
            git_hosts.each do |host|
              SharedHelpers.configure_git_to_use_https(host)
            end
            Dependabot.logger.info("Configured git rewrite rules for #{git_hosts.length} vanity import host(s)")
          end
        rescue StandardError => e
          # Log the error but don't fail the entire update process
          # Vanity import resolution is an optimization, not a requirement
          Dependabot.logger.warn("Failed to configure vanity git hosts: #{e.message}")
        end
      end
    end
  end
end
