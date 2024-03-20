# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Elm
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("elm.json")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain an elm-package.json or an elm.json"
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []

        fetched_files << elm_json if elm_json

        # NOTE: We *do not* fetch the exact-dependencies.json file, as it is
        # recommended that this is not committed
        fetched_files
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def elm_json
        return @elm_json if defined?(@elm_json)

        @elm_json = T.let(fetch_file_if_present("elm.json"), T.nilable(Dependabot::DependencyFile))
      end
    end
  end
end

Dependabot::FileFetchers.register("elm", Dependabot::Elm::FileFetcher)
