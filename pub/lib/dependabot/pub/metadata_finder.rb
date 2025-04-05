# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"

module Dependabot
  module Pub
    extend T::Sig

    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        source = dependency.requirements.first&.dig(:source)
        if source&.dig("type") == "git"
          result = T.must(Source.from_url(source.dig("description", "url")))
          result.directory = source.dig("description", "path")
          result.commit = source.dig("description", "resolved-ref")
          return result
        end
        repository_url = source&.dig("description", "url") || "https://pub.dev"

        listing = repository_listing(repository_url)
        repo = listing.dig("latest", "pubspec", "repository")
        # The repository field did not always exist in pubspec.yaml, and some
        # packages specify a git repository in the "homepage" field.
        repo ||= listing.dig("latest", "pubspec", "homepage")
        return nil unless repo

        Source.from_url(repo)
      end

      sig { params(repository_url: String).returns(T::Hash[String, T.untyped]) }
      def repository_listing(repository_url)
        response = Dependabot::RegistryClient.get(url: "#{repository_url}/api/packages/#{dependency.name}")
        JSON.parse(response.body)
      end
    end
  end
end

Dependabot::MetadataFinders.register("pub", Dependabot::Pub::MetadataFinder)
