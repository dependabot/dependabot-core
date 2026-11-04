# typed: strong
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/pub/requirement_source"
require "dependabot/pub/package/registry_package"
require "dependabot/registry_client"

module Dependabot
  module Pub
    extend T::Sig

    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        source = RequirementSource.new(dependency.requirements.first)
        if source.type == "git"
          result = T.must(Source.from_url(source.description_string("url")))
          result.directory = source.description_string("path")
          result.commit = source.description_string("resolved-ref")
          return result
        end
        repository_url = (source.description_string("url") || "https://pub.dev").delete_suffix("/")

        repo = repository_listing(repository_url).source_url
        return nil unless repo

        Source.from_url(repo)
      end

      sig { params(repository_url: String).returns(Package::RegistryPackage) }
      def repository_listing(repository_url)
        response = Dependabot::RegistryClient.get(url: "#{repository_url}/api/packages/#{dependency.name}")
        Package::RegistryPackage.from_json(response.body)
      end
    end
  end
end

Dependabot::MetadataFinders.register("pub", Dependabot::Pub::MetadataFinder)
