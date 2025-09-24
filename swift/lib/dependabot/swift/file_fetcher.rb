# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Swift
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("Package.swift")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a Package.swift configuration file."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files << package_manifest
        fetched_files << package_resolved if package_resolved
        fetched_files
      end

      private

      sig { returns(Dependabot::DependencyFile) }
      def package_manifest
        @package_manifest ||= T.let(fetch_file_from_host("Package.swift"), T.nilable(DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def package_resolved
        @package_resolved = T.let(fetch_file_if_present("Package.resolved"), T.nilable(DependencyFile))
      end
    end
  end
end

Dependabot::FileFetchers
  .register("swift", Dependabot::Swift::FileFetcher)
