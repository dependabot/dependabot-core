# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Nix
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("flake.nix") && filenames.include?("flake.lock")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a flake.nix and flake.lock file."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Nix support is currently in beta. Set ALLOW_BETA_ECOSYSTEMS=true to enable it."
          )
        end

        fetched_files = []
        fetched_files << flake_nix
        fetched_files << flake_lock
        fetched_files
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        nil
      end

      private

      sig { returns(Dependabot::DependencyFile) }
      def flake_nix
        @flake_nix ||=
          T.let(
            fetch_file_from_host("flake.nix"),
            T.nilable(Dependabot::DependencyFile)
          )
      end

      sig { returns(Dependabot::DependencyFile) }
      def flake_lock
        @flake_lock ||=
          T.let(
            fetch_file_from_host("flake.lock"),
            T.nilable(Dependabot::DependencyFile)
          )
      end
    end
  end
end

Dependabot::FileFetchers.register("nix", Dependabot::Nix::FileFetcher)
