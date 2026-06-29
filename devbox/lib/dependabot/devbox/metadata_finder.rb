# typed: strict
# frozen_string_literal: true

require "cgi"
require "json"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"

module Dependabot
  module Devbox
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      SEARCH_URL = T.let("https://search.devbox.sh/v1/search", String)

      private

      # nixpkgs packages expose a `homepage` in the Nixhub search response. When
      # it points at a recognised git host (e.g. GitHub) we can surface changelog
      # and release metadata; otherwise there is no usable source.
      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        homepage = nixhub_homepage
        return nil unless homepage

        Source.from_url(homepage)
      end

      sig { returns(T.nilable(String)) }
      def nixhub_homepage
        homepage = package_versions.filter_map { |v| v["homepage"] if v.is_a?(Hash) }.first
        homepage.is_a?(String) && !homepage.empty? ? homepage : nil
      rescue JSON::ParserError, Excon::Error::Timeout, Excon::Error::Socket
        nil
      end

      # The versions list for the exact-name package in the Nixhub search
      # response (search is fuzzy, so match the name precisely).
      sig { returns(T::Array[T.anything]) }
      def package_versions
        response = Dependabot::RegistryClient.get(
          url: "#{SEARCH_URL}?q=#{CGI.escape(dependency.name)}"
        )
        return [] unless response.status == 200

        data = JSON.parse(response.body)
        packages = data.is_a?(Hash) ? data["packages"] : nil
        return [] unless packages.is_a?(Array)

        package = packages.find { |pkg| pkg.is_a?(Hash) && pkg["name"] == dependency.name }
        versions = package.is_a?(Hash) ? package["versions"] : nil
        versions.is_a?(Array) ? versions : []
      end
    end
  end
end

Dependabot::MetadataFinders.register("devbox", Dependabot::Devbox::MetadataFinder)
