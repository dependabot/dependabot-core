# typed: strong
# frozen_string_literal: true

require "excon"
require "json"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/opentofu/registry_client"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Opentofu
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        case new_source_type
        when "git" then find_source_from_git_url
        when "registry", "provider" then find_source_from_registry_details
        when "oci" then find_source_from_oci_details
        else raise "Unexpected source type: #{new_source_type}"
        end
      end

      sig { returns(T.nilable(String)) }
      def new_source_type
        dependency.source_type
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_git_url
        url = T.must(dependency.source_string("url", allowed_types: ["git"]))
        Source.from_url(url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_oci_details
        artifact_identifier = dependency.source_string("artifact_identifier", allowed_types: ["oci"])
        return unless artifact_identifier

        hostname, repo = artifact_identifier.split("/", 2)
        return unless repo

        Source.new(
          provider: "oci",
          repo: repo,
          hostname: hostname,
          api_endpoint: "https://#{hostname}/"
        )
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_registry_details
        hostname = dependency.source_string(
          "registry_hostname",
          allowed_types: %w(registry provider)
        ) || RegistryClient::PUBLIC_HOSTNAME

        RegistryClient
          .new(hostname: hostname, credentials: credentials)
          .source(dependency: dependency)
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("opentofu", Dependabot::Opentofu::MetadataFinder)
