# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"

module Dependabot
  module Cargo
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      SOURCE_KEYS = %w(repository homepage documentation).freeze
      CRATES_IO_API = "https://crates.io/api/v1/crates"

      sig { params(dependency: Dependabot::Dependency, credentials: T::Array[Dependabot::Credential]).void }
      def initialize(dependency:, credentials:)
        super
        @crates_listing = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
      end

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        case new_source_type
        when "default" then find_source_from_crates_listing
        when "registry" then find_source_from_crates_listing
        when "git" then find_source_from_git_url
        else raise "Unexpected source type: #{new_source_type}"
        end
      end

      sig { returns(T.nilable(String)) }
      def new_source_type
        dependency.source_type
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_crates_listing
        potential_source_urls =
          SOURCE_KEYS
          .filter_map { |key| T.must(crates_listing).dig("crate", key) }

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
      def crates_listing
        return @crates_listing unless @crates_listing.nil?

        info = dependency.requirements.filter_map { |r| r[:source] }.first
        index = (info && info[:index]) || CRATES_IO_API
        hdrs = build_headers(index, info)

        url = metadata_fetch_url(dependency, index)
        response = fetch_metadata(url, hdrs)

        @crates_listing = parse_response(response, index)
      end

      sig { params(index: String, info: T.nilable(T::Hash[String, T.untyped])).returns(T::Hash[String, String]) }
      def build_headers(index, info)
        hdrs = { "User-Agent" => "Dependabot (dependabot.com)" }
        return hdrs if index == CRATES_IO_API

        return hdrs if info.nil?

        credentials.find { |cred| cred["type"] == "cargo_registry" && cred["registry"] == info["name"] }&.tap do |cred|
          hdrs["Authorization"] = "Token #{cred['token']}"
        end

        hdrs
      end

      sig { params(url: String, headers: T::Hash[String, String]).returns(Excon::Response) }
      def fetch_metadata(url, headers)
        Excon.get(
          url,
          idempotent: true,
          **SharedHelpers.excon_defaults(headers: headers)
        )
      end

      sig { params(response: Excon::Response, index: String).returns(T::Hash[String, T.untyped]) }
      def parse_response(response, index)
        if index.start_with?("sparse+")
          parsed_response = response.body.lines.map { |line| JSON.parse(line) }
          { "versions" => parsed_response }
        else
          JSON.parse(response.body)
        end
      end

      sig { params(dependency: Dependabot::Dependency, index: String).returns(String) }
      def metadata_fetch_url(dependency, index)
        return "#{index}/#{dependency.name}" if index == CRATES_IO_API

        # Determine cargo's index file path for the dependency
        index = index.delete_prefix("sparse+")
        name_length = dependency.name.length
        dependency_path = case name_length
                          when 1, 2
                            "#{name_length}/#{dependency.name}"
                          when 3
                            "#{name_length}/#{dependency.name[0..1]}/#{dependency.name}"
                          else
                            "#{dependency.name[0..1]}/#{dependency.name[2..3]}/#{dependency.name}"
                          end

        "#{index}#{'/' unless index.end_with?('/')}#{dependency_path}"
      end
    end
  end
end

Dependabot::MetadataFinders.register("cargo", Dependabot::Cargo::MetadataFinder)
