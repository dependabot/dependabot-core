# typed: strong
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/nuget/native_discovery/native_discovery_json_reader"
require "dependabot/nuget/native_helpers"
require "set"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |name| name.match?(/\.(cs|vb|fs)proj$/) }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain .(cs|vb|fs)proj file."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        discovery_json_reader = NativeDiscoveryJsonReader.run_discovery_in_directory(
          repo_contents_path: T.must(repo_contents_path),
          directory: directory,
          credentials: credentials
        )

        NativeDiscoveryJsonReader.debug_report_discovery_files(error_if_missing: false)
        discovery_json_reader.dependency_file_paths.map do |p|
          relative_path = Pathname.new(p).relative_path_from(directory).to_path
          fetch_file_from_host(relative_path)
        end
      end
    end
  end
end

Dependabot::FileFetchers.register("nuget", Dependabot::Nuget::FileFetcher)
