# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/clojure/constants"
require "dependabot/clojure/package_manager"

module Dependabot
  module Clojure
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?(LEIN_FILE_NAME) || filenames.include?(DEPS_FILE_NAME)
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a #{LEIN_FILE_NAME} or a #{DEPS_FILE_NAME} file."
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        fetched_files = [lein_files, deps_files].compact

        return fetched_files if fetched_files.any?

        raise Dependabot::DependencyFileNotFound.new(
          nil,
          self.class.required_files_message
        )
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lein_files = fetch_file_if_present(LEIN_FILE_NAME)

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def deps_files = fetch_file_if_present(DEPS_FILE_NAME)

    end
  end
end

Dependabot::FileFetchers.register(Dependabot::Clojure::ECOSYSTEM, Dependabot::Clojure::FileFetcher)
