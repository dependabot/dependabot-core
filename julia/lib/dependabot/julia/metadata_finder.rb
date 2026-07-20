# typed: strong
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/julia/registry_client"
require "uri" # Required for URI.parse

module Dependabot
  module Julia
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      # The public source_url method is inherited from Base.
      # We need to implement look_up_source as a private method.

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        # Only use authoritative sources from Julia helper
        url_string = source_url_from_julia_helper

        return nil unless url_string

        parse_source_url(url_string)
      end

      sig { returns(T.nilable(String)) }
      def source_url_from_julia_helper
        uuid = T.cast(dependency.metadata[:julia_uuid], T.nilable(String))
        result = registry_client.find_package_source_url(dependency.name, uuid)
        error = T.cast(result["error"], T.nilable(T.any(String, T::Boolean)))
        return nil if error

        T.cast(result["source_url"], T.nilable(String))
      rescue StandardError => e
        Dependabot.logger.warn("Failed to get source URL from Julia helper: #{e.message}")
        nil
      end

      sig { returns(Dependabot::Julia::RegistryClient) }
      def registry_client
        @registry_client ||= T.let(
          Dependabot::Julia::RegistryClient.new(
            credentials: credentials
          ),
          T.nilable(Dependabot::Julia::RegistryClient)
        )
      end

      sig { params(url_string: String).returns(T.nilable(Dependabot::Source)) }
      def parse_source_url(url_string)
        # Source.from_url understands all providers Dependabot supports
        # (GitHub, GitLab, Bitbucket, Azure DevOps, ...), unlike a
        # hand-rolled hostname switch
        source = Dependabot::Source.from_url(url_string)
        Dependabot.logger.info("Unknown SCM provider for #{url_string}") if source.nil?
        source
      end
    end
  end
end

Dependabot::MetadataFinders.register("julia", Dependabot::Julia::MetadataFinder)
