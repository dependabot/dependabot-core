# typed: true
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Swift
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      def self.required_files_in?(filenames)
        filenames.include?("Package.swift")
      end

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

      def package_manifest
        @package_manifest ||= fetch_file_from_host("Package.swift")
      end

      def package_resolved
        return @package_resolved if defined?(@package_resolved)

        @package_resolved = fetch_file_if_present("Package.resolved")
      end
    end
  end
end

Dependabot::FileFetchers
  .register("swift", Dependabot::Swift::FileFetcher)
