# typed: strict
# frozen_string_literal: true

# This class is responsible for coordinating the creation and upkeep of Pull Requests for
# a given folder's defined DependencyGroups.
#
# - If there is no Pull Request already open for a DependencyGroup, it will be delegated
#   to Dependabot::Updater::Operations::CreateGroupUpdatePullRequest.
# - If there is an open Pull Request for a DependencyGroup, it will skip over that group
#   as the service is responsible for refreshing it in a separate job.
# - Any ungrouped Dependencies will be handled individually by delegation to
#   Dependabot::Updater::Operations::UpdateAllVersions.
#

module Dependabot
  class Updater
    module Operations
      class OsvFix
        include PullRequestHelpers
        extend T::Sig

        module OSVScanner
          extend T::Sig
          extend T::Helpers

          Package = Struct.new(:source_file, :name, :version)

          sig { params(manifest_path: String).returns(T::Array[Package]) }
          def self.scan(manifest_path:)
            JSON.parse(cached_osv_scan(manifest_path:)).fetch("results").flat_map do |result|
              result.fetch("packages").map do |package|
                Package.new(
                  source_file: result.dig("source", "path"),
                  name: package.dig("package", "name"),
                  version: package.dig("package", "version")
                )
              end
            end
          end

          sig { params(manifest_path: String).void }
          def self.fix(manifest_path:)
            return if File.exist?(osv_scanner_resolution_file_path(manifest_path:))

            command_args = %W(fix
                              --non-interactive --maven-fix-management
                              --experimental-offline --data-source native
                              -M #{manifest_path})
            run(args: command_args)

            # after applying a fix, remove any cached scan information
            # File.unlink(cached_osv_scan_location(pomfile_path:)) if File.exist?(cached_osv_scan_location(pomfile_path:))
          end

          sig { params(manifest_path: String).returns(String) }
          def self.osv_scanner_resolution_file_path(manifest_path:)
            File.join(File.dirname(manifest_path), "pom.xml.resolve.maven")
          end

          sig { params(manifest_path: String).returns(String) }
          def self.cached_osv_scan(manifest_path:)
            cached_location = cached_osv_scan_location(manifest_path:)
            return File.read(cached_location) if File.exist?(cached_location)

            command_args = %W(scan --experimental-offline --experimental-all-packages --format json
                              #{File.dirname(manifest_path)})
            run(args: command_args).tap { |output| File.write(cached_location, output) }
          end

          sig { params(manifest_path: String).returns(String) }
          def self.cached_osv_scan_location(manifest_path:)
            File.join(File.dirname(manifest_path), "osv_scan.json")
          end

          sig { params(args: T::Array[String]).returns(String) }
          def self.run(args: [])
            start = Time.now

            command = SharedHelpers.escape_command("osv-scanner #{args.join(' ')}")

            # Pass through any OSV_ environment variables
            env = ENV.select { |key, _value| key.match(/^OSV_/) }

            stdout, stderr, process = Open3.capture3(env, command)
            time_taken = Time.now - start

            # Raise an error with the output from the shell session if osv-scanner
            # returns a status > 1
            return stdout if T.must(process.exitstatus) <= 1

            raise SharedHelpers::HelperSubprocessFailed.new(
              message: stderr,
              error_context: {
                command: command,
                time_taken: time_taken,
                process_exit_value: process.to_s
              }
            )
          end
        end

        sig { params(job: Dependabot::Job).returns(T::Boolean) }
        def self.applies_to?(job:)
          job.package_manager.end_with?("_osv")
        end

        sig { returns(Symbol) }
        def self.tag_name
          :osv_fix
        end

        sig do
          params(
            service: Dependabot::Service,
            job: Dependabot::Job,
            dependency_snapshot: Dependabot::DependencySnapshot,
            error_handler: Dependabot::Updater::ErrorHandler
          ).void
        end
        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
        end

        sig { void }
        def perform
          Dependabot.logger.info("Starting PR update job for #{job.source.repo}")

          pomfiles.each do |pom|
            OSVScanner.fix(manifest_path: File.join(job.repo_contents_path, pom.realpath))
          end


          updated_dependency_files = Dependabot::FileFetchers.for_package_manager(job.package_manager).new(
            source: job.source,
            credentials: job.credentials,
            repo_contents_path: job.repo_contents_path
          ).files

          updated_dependencies = Dependabot::FileParsers.for_package_manager(job.package_manager).new(
            dependency_files: updated_dependency_files,
            repo_contents_path: job.repo_contents_path,
            source: job.source,
            credentials: job.credentials,
            reject_external_code: job.reject_external_code?,
            options: job.experiments
          ).parse

          updated_dependencies = updated_dependencies.filter_map do |updated_dep|
            previous_dep = dependency_snapshot.dependencies.find do |original_dep|
              next false unless updated_dep.directory == original_dep.directory
              next false unless updated_dep.source_details == original_dep.source_details

              updated_dep.name == original_dep.name
            end

            next if previous_dep && previous_dep.version == updated_dep.version

            Dependabot::Dependency.new(
              name: updated_dep.name,
              requirements: updated_dep.requirements,
              package_manager: updated_dep.package_manager,
              version: updated_dep.version,
              previous_version: previous_dep&.version,
              previous_requirements: previous_dep&.requirements,
              directory: updated_dep.directory,
              subdependency_metadata: updated_dep.subdependency_metadata,
              removed: updated_dep.removed?,
              metadata: updated_dep.metadata
            )
          end

          dependency_change = Dependabot::DependencyChange.new(
            job: job,
            updated_dependencies: updated_dependencies,
            updated_dependency_files: updated_dependency_files,
            dependency_group: nil,
            notices: []
          )

          # Raise an error if the package manager version is unsupported
          dependency_snapshot.package_manager&.raise_if_unsupported!

          if dependency_change.updated_dependency_files.empty?
            raise "UpdateChecker found viable dependencies to be updated, but FileUpdater failed to update any files"
          end

          create_pull_request(dependency_change)
        end

        private

        sig { returns(Dependabot::Job) }
        attr_reader :job

        sig { returns(Dependabot::Service) }
        attr_reader :service

        sig { returns(DependencySnapshot) }
        attr_reader :dependency_snapshot

        sig { returns(Dependabot::Updater::ErrorHandler) }
        attr_reader :error_handler

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def pomfiles
          @pomfiles ||= T.let(
            dependency_snapshot.dependency_files.select do |f|
              f.name.end_with?(".xml") && !f.name.end_with?("extensions.xml")
            end,
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { params(dependency_change: Dependabot::DependencyChange).void }
        def create_pull_request(dependency_change)
          Dependabot.logger.info("Submitting #{dependency_change.updated_dependencies.map(&:name).join(', ')} " \
                                 "pull request for creation")

          service.create_pull_request(dependency_change, dependency_snapshot.base_commit_sha)

          PullRequest.create_from_updated_dependencies(dependency_change.updated_dependencies)
        end
      end
    end
  end
end
