# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/logger"
require "dependabot/shared_helpers"
require "dependabot/go_modules/vanity_import_resolver"

module Dependabot
  module GoModules
    class FileUpdater
      module UpdaterHelper
        extend T::Sig

        # Configure git rewrite rules for vanity import hosts
        # This prevents SSH URL failures when Go toolchain discovers git hosts from vanity imports
        sig { params(dependencies: T::Array[Dependabot::Dependency]).void }
        def self.configure_git_vanity_imports(dependencies)
          return unless dependencies.any?

          resolver = Dependabot::GoModules::VanityImportResolver.new(dependencies: dependencies)
          return unless resolver.has_vanity_imports?

          begin
            git_hosts = resolver.resolve_git_hosts

            if git_hosts.any?
              git_hosts.each do |host|
                SharedHelpers.configure_git_to_use_https(host)
              end
              Dependabot.logger.info("Configured git rewrite rules for #{git_hosts.length} vanity import host(s)")
            end
          rescue => e
            # Log the error but don't fail the entire update process
            # Vanity import resolution is an optimization, not a requirement
            Dependabot.logger.warn("Failed to configure vanity git hosts: #{e.message}")
          end
        end
      end
    end
  end
end
