# typed: true
# frozen_string_literal: true

require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/update_checker/registry_finder"
require "dependabot/npm_and_yarn/registry_parser"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      class BunLockfileUpdater
        require_relative "npmrc_builder"
        require_relative "package_json_updater"

        def initialize(dependencies:, dependency_files:, repo_contents_path:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        def updated_bun_lock_content(bun_lock)
          @updated_bun_lock_content ||= {}
          return @updated_bun_lock_content[bun_lock.name] if @updated_bun_lock_content[bun_lock.name]

          new_content = run_bun_update(bun_lock: bun_lock)
          @updated_bun_lock_content[bun_lock.name] = new_content
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_bun_lock_updater_error(e, bun_lock)
        end

        private

        attr_reader :dependencies
        attr_reader :dependency_files
        attr_reader :repo_contents_path
        attr_reader :credentials

        ERR_PATTERNS = {
          /get .* 404/i => Dependabot::DependencyNotFound,
          /installfailed cloning repository/i => Dependabot::DependencyNotFound,
          /file:.* failed to resolve/i => Dependabot::DependencyNotFound,
          /no version matching/i => Dependabot::DependencyFileNotResolvable,
          /failed to resolve/i => Dependabot::DependencyFileNotResolvable
        }.freeze

        def run_bun_update(bun_lock:)
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            File.write(".npmrc", npmrc_content(bun_lock))

            SharedHelpers.with_git_configured(credentials: credentials) do
              run_bun_updater

              write_final_package_json_files

              run_bun_install

              File.read(bun_lock.name)
            end
          end
        end

        def run_bun_updater
          dependency_updates = dependencies.map do |d|
            "#{d.name}@#{d.version}"
          end.join(" ")

          Helpers.run_bun_command(
            "install #{dependency_updates} --save-text-lockfile",
            fingerprint: "install <dependency_updates> --save-text-lockfile"
          )
        end

        def run_bun_install
          Helpers.run_bun_command(
            "install --save-text-lockfile"
          )
        end

        def lockfile_dependencies(lockfile)
          @lockfile_dependencies ||= {}
          @lockfile_dependencies[lockfile.name] ||=
            NpmAndYarn::FileParser.new(
              dependency_files: [lockfile, *package_files],
              source: nil,
              credentials: credentials
            ).parse
        end

        def handle_bun_lock_updater_error(error, _bun_lock)
          error_message = error.message

          ERR_PATTERNS.each do |pattern, error_class|
            raise error_class, error_message if error_message.match?(pattern)
          end

          raise error
        end

        def write_final_package_json_files
          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, updated_package_json_content(file))
          end
        end

        def npmrc_content(bun_lock)
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files,
            dependencies: lockfile_dependencies(bun_lock)
          ).npmrc_content
        end

        def updated_package_json_content(file)
          @updated_package_json_content ||= {}
          @updated_package_json_content[file.name] ||=
            PackageJsonUpdater.new(
              package_json: file,
              dependencies: dependencies
            ).updated_package_json.content
        end

        def package_files
          @package_files ||= dependency_files.select { |f| f.name.end_with?("package.json") }
        end

        def base_dir
          dependency_files.first.directory
        end

        def npmrc_file
          dependency_files.find { |f| f.name == ".npmrc" }
        end

        def sanitize_message(message)
          message.gsub(/"|\[|\]|\}|\{/, "")
        end
      end
    end
  end
end
