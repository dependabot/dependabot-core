# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

require "dependabot/vcpkg"

module Dependabot
  module Vcpkg
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?(VCPKG_JSON_FILENAME)
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a vcpkg.json file."
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        [vcpkg_manifest, vcpkg_configuration].compact
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def vcpkg_manifest
        @vcpkg_manifest ||= T.let(
          fetch_file_if_present(VCPKG_JSON_FILENAME),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def vcpkg_configuration
        @vcpkg_configuration ||= T.let(
          fetch_file_if_present(VCPKG_CONFIGURATION_JSON_FILENAME),
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::FileFetchers.register("vcpkg", Dependabot::Vcpkg::FileFetcher)
