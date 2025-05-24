# typed: strong
# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"
require "dependabot/julia/registry_client"
require "uri" # Required for URI.parse
require "toml-rb" # Required for TOML parsing

module Dependabot
  module Julia
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      # The public source_url method is inherited from Base.
      # We need to implement look_up_source as a private method.

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        # Only use authoritative sources from Julia helper or dependency files
        url_string = source_url_from_julia_helper ||
                     source_url_from_dependency_files

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
        uri = URI.parse(url_string)
        hostname = uri.host
        return nil unless hostname

        # Extract repository path and clean it
        path = T.must(uri.path).delete_prefix("/").delete_suffix(".git")
        path_parts = path.split("/")
        return nil if path_parts.length < 2

        repo = "#{path_parts[0]}/#{path_parts[1]}"

        # Determine the provider based on hostname
        provider = case hostname
                   when "github.com" then "github"
                   when "gitlab.com" then "gitlab"
                   when /\A.*\.gitlab\.io\z/ then "gitlab"
                   else
                     Dependabot.logger.info("Unknown SCM provider for #{hostname}, using generic")
                     return nil # Return nil for unknown providers
                   end

        Dependabot::Source.new(
          provider: provider,
          repo: repo
        )
      rescue URI::InvalidURIError => e
        Dependabot.logger.error("Invalid URI for dependency #{dependency.name}: #{url_string} - #{e.message}")
        nil
      end

      sig { returns(T.nilable(String)) }
      def source_url_from_dependency_files
        # MetadataFinder doesn't have access to dependency_files
        # This would typically be handled by FileParser or other components
        # For now, we'll skip this strategy and rely on the Julia helper
        nil
      end
    end
  end
end

Dependabot::MetadataFinders.register("julia", Dependabot::Julia::MetadataFinder)
