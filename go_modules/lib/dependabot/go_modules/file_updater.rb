# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/shared_helpers"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/file_updaters/vendor_updater"

module Dependabot
  module GoModules
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/go_mod_updater"

      sig do
        override
          .params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String),
            options: T::Hash[Symbol, T.untyped]
          )
          .void
      end
      def initialize(dependencies:, dependency_files:, credentials:, repo_contents_path: nil, options: {})
        super

        @goprivate = T.let(options.fetch(:goprivate, "*"), String)
        use_repo_contents_stub if repo_contents_path.nil?
      end

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /^go\.mod$/,
          /^go\.sum$/
        ]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        if go_mod && dependency_changed?(T.must(go_mod))
          updated_files <<
            updated_file(
              file: T.must(go_mod),
              content: T.must(file_updater.updated_go_mod_content)
            )

          if go_sum && T.must(go_sum).content != file_updater.updated_go_sum_content
            updated_files <<
              updated_file(
                file: T.must(go_sum),
                content: T.must(file_updater.updated_go_sum_content)
              )
          end

          vendor_updater.updated_files(base_directory: T.must(directory))
                        .each do |file|
            updated_files << file
          end
        end

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { params(go_mod: Dependabot::DependencyFile).returns(T::Boolean) }
      def dependency_changed?(go_mod)
        # file_changed? only checks for changed requirements. Need to check for indirect dep version changes too.
        file_changed?(go_mod) || dependencies.any? { |dep| dep.previous_version != dep.version }
      end

      sig { override.void }
      def check_required_files
        return if go_mod

        raise "No go.mod!"
      end

      sig { returns(String) }
      def use_repo_contents_stub
        @repo_contents_stub = T.let(true, T.nilable(T::Boolean))
        @repo_contents_path = Dir.mktmpdir

        Dir.chdir(@repo_contents_path) do
          dependency_files.each do |file|
            path = File.join(@repo_contents_path, directory, file.name)
            path = Pathname.new(path).expand_path
            FileUtils.mkdir_p(path.dirname)
            File.write(path, file.content)
          end

          # Only used to create a backup git config that's reset
          SharedHelpers.with_git_configured(credentials: []) do
            `git config --global user.email "no-reply@github.com"`
            `git config --global user.name "Dependabot"`
            `git config --global init.defaultBranch "placeholder-default-branch"`
            `git init .`
            `git add .`
            `git commit -m'fake repo_contents_path'`
          end
        end
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_mod
        @go_mod ||= T.let(get_original_file("go.mod"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_sum
        @go_sum ||= T.let(get_original_file("go.sum"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(String)) }
      def directory
        dependency_files.first&.directory
      end

      sig { returns(String) }
      def vendor_dir
        File.join(repo_contents_path, directory, "vendor")
      end

      sig { returns(Dependabot::FileUpdaters::VendorUpdater) }
      def vendor_updater
        Dependabot::FileUpdaters::VendorUpdater.new(
          repo_contents_path: repo_contents_path,
          vendor_dir: vendor_dir
        )
      end

      sig { returns(GoModUpdater) }
      def file_updater
        @file_updater ||= T.let(
          GoModUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path,
            directory: T.must(directory),
            options: { tidy: tidy?, vendor: vendor?, goprivate: @goprivate }
          ),
          T.nilable(Dependabot::GoModules::FileUpdater::GoModUpdater)
        )
      end

      sig { returns(T::Boolean) }
      def tidy?
        !@repo_contents_stub
      end

      sig { returns(T::Boolean) }
      def vendor?
        File.exist?(File.join(vendor_dir, "modules.txt"))
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("go_modules", Dependabot::GoModules::FileUpdater)
