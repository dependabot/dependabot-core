# typed: strict
# frozen_string_literal: true

require "excon"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"
require "sorbet-runtime"

module Dependabot
  module Hex
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      SOURCE_KEYS = T.let(%w(
        GitHub Github github
        GitLab Gitlab gitlab
        BitBucket Bitbucket bitbucket
        Source source
      ).freeze, T::Array[String])

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        case new_source_type
        when "default" then find_source_from_hex_listing
        when "git" then find_source_from_git_url
        else raise "Unexpected source type: #{new_source_type}"
        end
      end

      sig { returns(T.nilable(String)) }
      def new_source_type
        dependency.source_type
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_hex_listing
        potential_source_urls =
          SOURCE_KEYS
          .filter_map { |key| T.must(hex_listing).dig("meta", "links", key) }

        source_url = potential_source_urls.find { |url| Source.from_url(url) }
        Source.from_url(source_url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_git_url
        info = dependency.requirements.filter_map { |r| r[:source] }.first

        url = info[:url] || info.fetch("url")
        Source.from_url(url)
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def hex_listing
        return @hex_listing unless @hex_listing.nil?

        response = Dependabot::RegistryClient.get(url: "https://hex.pm/api/packages/#{dependency.name}")
        @hex_listing = T.let(JSON.parse(response.body), T.nilable(T::Hash[String, T.untyped]))
      end
    end
  end
end

Dependabot::MetadataFinders.register("hex", Dependabot::Hex::MetadataFinder)
