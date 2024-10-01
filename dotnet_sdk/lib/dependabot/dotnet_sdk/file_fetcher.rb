# typed: strong
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "sorbet-runtime"

module Dependabot
  module DotnetSdk
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.end_with?("global.json") }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a global.json file."
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files << root_file

        return fetched_files if fetched_files.any?

        raise Dependabot::DependencyFileNotFound.new(
          nil,
          "global.json not found in #{directory}"
        )
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def root_file
        fetch_file_if_present("global.json")
      end
    end
  end
end

Dependabot::FileFetchers.register("dotnet_sdk", Dependabot::DotnetSdk::FileFetcher)
