# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Luarocks
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      ROCKSPEC_EXTENSION = ".rockspec"

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a .rockspec file."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |name| name.end_with?(ROCKSPEC_EXTENSION) }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "LuaRocks is currently in beta. Please contact Dependabot support to enable it."
          )
        end

        fetched_files = []
        fetched_files.concat(rockspec_files)

        return fetched_files if fetched_files.any?

        raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message)
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        { package_managers: { "luarocks" => "1.0.0" } }
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def rockspec_files
        repo_contents(raise_errors: false)
          .select { |file| file.type == "file" && file.name.end_with?(ROCKSPEC_EXTENSION) }
          .map { |file| fetch_file_from_host(file.name) }
      end
    end
  end
end

Dependabot::FileFetchers.register("luarocks", Dependabot::Luarocks::FileFetcher)
