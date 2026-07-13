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
        @crates_listing = T.let(nil, T.nilable(T::Hash[String, T.anything]))
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
          .filter_map do |key|
            crate = T.cast(T.must(crates_listing)["crate"], T.nilable(T::Hash[String, T.anything]))
            T.cast(crate&.fetch(key, nil), T.nilable(String))
          end

        source_url = potential_source_urls.find { |url| Source.from_url(url) }
        Source.from_url(source_url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_git_url
        info = T.cast(
          dependency.requirements.filter_map { |r| r[:source] }.first,
          T.nilable(T::Hash[T.any(String, Symbol), T.anything])
        )
        return unless info

        url = info[:url] || info["url"]
        Source.from_url(T.cast(url, T.nilable(String)))
      end

      sig { returns(T.nilable(T::Hash[String, T.anything])) }
      def crates_listing
        return @crates_listing unless @crates_listing.nil?

        info = T.cast(
          dependency.requirements.filter_map { |r| r[:source] }.first,
          T.nilable(T::Hash[T.any(String, Symbol), T.anything])
        )
        index = T.cast((info && (info[:index] || info["index"])) || CRATES_IO_API, String)
        hdrs = build_headers(index, info)

        url = metadata_fetch_url(dependency, index)
        response = fetch_metadata(url, hdrs)

        @crates_listing = parse_response(response, index)
      end

      sig do
        params(index: String, info: T.nilable(T::Hash[T.any(String, Symbol), T.anything]))
          .returns(T::Hash[String, String])
      end
      def build_headers(index, info)
        hdrs = { "User-Agent" => "Dependabot (dependabot.com)" }
        return hdrs if index == CRATES_IO_API

        return hdrs if info.nil?

        registry_name = T.cast(info["name"] || info[:name], T.nilable(String))
        credentials.find { |cred| cred["type"] == "cargo_registry" && cred["registry"] == registry_name }&.tap do |cred|
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

      sig { params(response: Excon::Response, index: String).returns(T::Hash[String, T.anything]) }
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
