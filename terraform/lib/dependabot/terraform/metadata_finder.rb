# typed: strong
# frozen_string_literal: true

require "excon"
require "json"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/terraform/registry_client"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Terraform
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        case new_source_type
        when "git" then find_source_from_git_url
        when "registry", "provider" then find_source_from_registry_details
        else raise "Unexpected source type: #{new_source_type}"
        end
      end

      sig { returns(T.nilable(String)) }
      def new_source_type
        dependency.source_type
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_git_url
        info = dependency.requirements.filter_map(&:source).first

        url = source_string(info, "url")
        Source.from_url(url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_registry_details
        info = dependency.requirements.filter_map(&:source).first
        hostname = source_string(info, "registry_hostname") || RegistryClient::PUBLIC_HOSTNAME

        RegistryClient
          .new(hostname: hostname, credentials: credentials)
          .source(dependency: dependency)
      end

      sig do
        params(
          source: T.nilable(Dependabot::DependencyRequirement::Details),
          key: String
        ).returns(T.nilable(String))
      end
      def source_string(source, key)
        return unless source

        value = source[key] || source[key.to_sym]
        value if value.is_a?(String)
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("terraform", Dependabot::Terraform::MetadataFinder)
