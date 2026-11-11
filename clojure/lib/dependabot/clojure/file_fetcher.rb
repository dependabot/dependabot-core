# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/clojure/constants"

module Dependabot
  module Clojure
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      BETA_DISABLED_MESSAGE = T.let(
        "clojure is a beta ecosystem. Set `enable-beta-ecosystems: true` in your " \
        "dependabot.yml so Dependabot fetches and updates #{LEIN_FILE_NAME} and #{DEPS_FILE_NAME}.".freeze,
        String
      )

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?(LEIN_FILE_NAME) || filenames.include?(DEPS_FILE_NAME)
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a #{LEIN_FILE_NAME} or a #{DEPS_FILE_NAME} file."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        # Tell the user how to opt in, rather than claim the manifest is missing.
        raise Dependabot::DependencyFileNotFound.new(nil, BETA_DISABLED_MESSAGE) unless allow_beta_ecosystems?

        fetched_files = [LEIN_FILE_NAME, DEPS_FILE_NAME].filter_map { |name| fetch_file_if_present(name) }
        return fetched_files if fetched_files.any?

        raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message)
      end
    end
  end
end

Dependabot::FileFetchers.register(Dependabot::Clojure::ECOSYSTEM, Dependabot::Clojure::FileFetcher)
