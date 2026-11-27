# typed: strong
# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/logger"
require "dependabot/swift/file_updater/host_only_pins"
require "sorbet-runtime"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      class LockfileUpdater
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            manifest: Dependabot::DependencyFile,
            repo_contents_path: String,
            credentials: T::Array[Dependabot::Credential],
            target_version: T.nilable(String),
            remove_host_only_pins: T::Boolean
          )
            .void
        end
        def initialize(
          dependency:,
          manifest:,
          repo_contents_path:,
          credentials:,
          target_version: nil,
          remove_host_only_pins: false
        )
          @dependency = dependency
          @manifest = manifest
          @repo_contents_path = repo_contents_path
          @credentials = credentials
          @target_version = target_version
          @remove_host_only_pins = remove_host_only_pins
        end

        sig { returns(String) }
        def updated_lockfile_content
          SharedHelpers.in_a_temporary_repo_directory(manifest.directory, repo_contents_path) do
            SharedHelpers.with_git_configured(credentials: credentials) do
              dependency_name = T.must(dependency.metadata_string(:identity))
              host_only_pins = find_host_only_pins(dependency_name) if remove_host_only_pins

              File.write(manifest.name, manifest.content)
              try_lockfile_update(dependency_name)

              content = File.read("Package.resolved")
              host_only_pins ? host_only_pins.remove_from(content) : content
            end
          end
        end

        private

        # Finds the pins that SwiftPM only adds on this host by resolving the dependency at the version that is
        # already locked: SwiftPM rewrites Package.resolved for this host without updating anything. Then puts the
        # committed Package.resolved back.
        sig { params(dependency_name: String).returns(T.nilable(HostOnlyPins)) }
        def find_host_only_pins(dependency_name)
          previous_version = dependency.previous_version
          return unless previous_version && File.exist?("Package.resolved")

          committed = File.read("Package.resolved")
          begin
            SharedHelpers.run_shell_command(
              "swift package resolve #{dependency_name} --version #{previous_version}",
              fingerprint: "swift package resolve <dependency_name> --version <previous_version>"
            )
            pins = HostOnlyPins.new(committed: committed, resolved_on_host: File.read("Package.resolved"))
            if pins.keys.any?
              Dependabot.logger.info("Leaving out pins that SwiftPM only adds on this host: #{pins.keys.join(', ')}")
            end
            pins
          rescue SharedHelpers::HelperSubprocessFailed => e
            Dependabot.logger.info("Could not resolve the locked version to find host-only pins:\n#{e.message}")
            nil
          ensure
            File.write("Package.resolved", committed)
          end
        end

        sig { params(dependency_name: String).void }
        def try_lockfile_update(dependency_name)
          if target_version
            SharedHelpers.run_shell_command(
              "swift package resolve #{dependency_name} --version #{target_version}",
              fingerprint: "swift package resolve <dependency_name> --version <target_version>"
            )
          else
            SharedHelpers.run_shell_command(
              "swift package update #{dependency_name}",
              fingerprint: "swift package update <dependency_name>"
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          # This class is not only used for final lockfile updates, but for
          # checking resolvability. So resolvability errors here are expected in
          # certain situations and will result in `no_update_possible` outcomes.
          # That said, since we're swallowing all errors we at least log them to ease debugging.
          Dependabot.logger.info("Lockfile failed to be updated due to error:\n#{e.message}")
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { returns(String) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        attr_reader :target_version

        sig { returns(T::Boolean) }
        attr_reader :remove_host_only_pins
      end
    end
  end
end
