# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/metadata_finder"
require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/file_fetcher"
require "dependabot/metadata_finders"

module Dependabot
  module KotlinToolchain
    class MetadataFinder < Dependabot::Gradle::MetadataFinder
      extend T::Sig

      private

      sig { override.returns(T::Boolean) }
      def plugin?
        false
      end

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        return Dependabot::Source.from_url(KOTLIN_TOOLCHAIN_GITHUB_URL) if dependency.metadata[:wrapper]

        super
      end

      sig { override.returns(T.class_of(Dependabot::FileFetchers::Base)) }
      def file_fetcher_class
        Dependabot::KotlinToolchain::FileFetcher
      end
    end
  end
end

Dependabot::MetadataFinders.register(
  "kotlin_toolchain",
  Dependabot::KotlinToolchain::MetadataFinder
)
