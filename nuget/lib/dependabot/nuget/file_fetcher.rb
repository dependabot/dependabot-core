# typed: strong
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/nuget/discovery/discovery_json_reader"
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
        NativeHelpers.normalize_file_names
        NativeHelpers.install_dotnet_sdks
        discovery_json_reader = DiscoveryJsonReader.run_discovery_in_directory(
          repo_contents_path: T.must(repo_contents_path),
          directory: directory,
          credentials: credentials
        )

        discovery_json_reader.dependency_file_paths.map do |p|
          relative_path = Pathname.new(p).relative_path_from(directory).to_path
          fetch_file_from_host(relative_path)
        end
      end
    end
  end
end

Dependabot::FileFetchers.register("nuget", Dependabot::Nuget::FileFetcher)
