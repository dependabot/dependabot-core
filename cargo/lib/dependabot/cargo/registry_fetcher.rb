# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Cargo
    class RegistryFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("config.json")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a config.json"
      end

      sig { returns(String) }
      def dl
        T.must(parsed_config_json["dl"]).chomp("/")
      end

      sig { returns(String) }
      def api
        T.must(parsed_config_json["api"]).chomp("/")
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files << config_json
      end

      private

      sig { returns(T::Hash[String, String]) }
      def parsed_config_json
        @parsed_config_json ||= T.let(JSON.parse(T.must(config_json.content)), T.nilable(T::Hash[String, String]))
      end

      sig { returns(Dependabot::DependencyFile) }
      def config_json
        @config_json ||= T.let(fetch_file_from_host("config.json"), T.nilable(Dependabot::DependencyFile))
      end
    end
  end
end
