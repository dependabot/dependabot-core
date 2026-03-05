# typed: strict
# frozen_string_literal: true

require "json"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"

module Dependabot
  module Deno
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        source_type = dependency.requirements.first&.dig(:source, :type)

        case source_type
        when "npm"
          find_source_from_npm
        when "jsr"
          find_source_from_jsr
        end
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_npm
        response = Dependabot::RegistryClient.get(
          url: "https://registry.npmjs.org/#{dependency.name}"
        )
        data = JSON.parse(response.body)

        repo = data.dig("repository", "url")
        return nil unless repo

        Source.from_url(repo)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_jsr
        # JSR meta.json doesn't include repository info directly
        nil
      end
    end
  end
end

Dependabot::MetadataFinders.register("deno", Dependabot::Deno::MetadataFinder)
