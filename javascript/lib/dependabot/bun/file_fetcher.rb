# typed: strong
# frozen_string_literal: true

module Dependabot
  module Bun
    class FileFetcher < Dependabot::FileFetchers::Base
      include Javascript::FileFetcherHelper
      extend T::Sig
      extend T::Helpers

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("package.json")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a package.json."
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        return unknown_ecosystem_versions unless ecosystem_enabled?

        {
          package_managers: {
            "bun" => 1
          }
        }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = T.let([], T::Array[DependencyFile])
        fetched_files << package_json(self)
        fetched_files += bun_files if ecosystem_enabled?
        fetched_files += workspace_package_jsons(self)
        fetched_files += path_dependencies(self, fetched_files)

        fetched_files.uniq
      end

      sig { params(filename: String, fetch_submodules: T::Boolean).returns(DependencyFile) }
      def fetch_file(filename, fetch_submodules: false)
        fetch_file_from_host(filename, fetch_submodules: fetch_submodules)
      end

      sig do
        params(
          dir: T.any(Pathname, String),
          ignore_base_directory: T::Boolean,
          raise_errors: T::Boolean,
          fetch_submodules: T::Boolean
        )
          .returns(T::Array[T.untyped])
      end
      def fetch_repo_contents(dir: ".", ignore_base_directory: false, raise_errors: true, fetch_submodules: false)
        repo_contents(dir: dir, ignore_base_directory:, raise_errors:, fetch_submodules:)
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def bun_files
        [bun_lock].compact
      end

      sig { returns(T.nilable(DependencyFile)) }
      def bun_lock
        return @bun_lock if defined?(@bun_lock)

        @bun_lock ||= T.let(fetch_file_if_present(PackageManager::LOCKFILE_NAME), T.nilable(DependencyFile))

        return @bun_lock if @bun_lock || directory == "/"

        @bun_lock = fetch_file_from_parent_directories(self, PackageManager::LOCKFILE_NAME)
      end

      sig { returns(T::Boolean) }
      def ecosystem_enabled?
        allow_beta_ecosystems? && Experiments.enabled?(:enable_bun_ecosystem)
      end

      sig { returns(T::Hash[Symbol, String]) }
      def unknown_ecosystem_versions
        {
          package_managers: {
            "unknown" => 0
          }
        }
      end
    end
  end
end

Dependabot::FileFetchers
  .register(Dependabot::Bun::ECOSYSTEM, Dependabot::Bun::FileFetcher)
