# typed: strict
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
        info = dependency.requirements.filter_map { |r| r[:source] }.first

        url = info[:url] || info.fetch("url")
        Source.from_url(url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_registry_details
        info = dependency.requirements.filter_map { |r| r[:source] }.first
        hostname = info[:registry_hostname] || info["registry_hostname"]

        RegistryClient
          .new(hostname: hostname, credentials: credentials)
          .source(dependency: dependency)
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("terraform", Dependabot::Terraform::MetadataFinder)
