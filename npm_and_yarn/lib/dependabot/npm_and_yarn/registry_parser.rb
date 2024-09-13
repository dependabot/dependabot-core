# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class RegistryParser
      extend T::Sig

      sig { params(resolved_url: String, credentials: T::Array[Dependabot::Credential]).void }
      def initialize(resolved_url:, credentials:)
        @resolved_url = resolved_url
        @credentials = credentials
      end

      sig { params(name: String).returns(T::Hash[Symbol, T.untyped]) }
      def registry_source_for(name)
        url =
          if resolved_url.include?("/~/")
            # Gemfury format
            resolved_url.split("/~/").first
          elsif resolved_url.include?("/#{name}/-/#{name}")
            # MyGet / Bintray format
            T.must(resolved_url.split("/#{name}/-/#{name}").first)
             .gsub("dl.bintray.com//", "api.bintray.com/npm/").
              # GitLab format
              gsub(%r{\/projects\/\d+}, "")
          elsif resolved_url.include?("/#{name}/-/#{name.split('/').last}")
            # Sonatype Nexus / Artifactory JFrog format
            resolved_url.split("/#{name}/-/#{name.split('/').last}").first
          elsif (cred_url = url_for_relevant_cred) then cred_url
          else
            T.must(resolved_url.split("/")[0..2]).join("/")
          end

        { type: "registry", url: url }
      end

      sig { returns(String) }
      def dependency_name
        url_base = if resolved_url.include?("/-/")
                     T.must(resolved_url.split("/-/").first)
                   else
                     resolved_url
                   end

        package_name = url_base.gsub("%2F", "/").match(%r{@.*/})
        "#{T.must(package_name)}#{T.must(url_base.gsub('%2F', '/').split('/').last)}"
      end

      private

      sig { returns(String) }
      attr_reader :resolved_url

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      # rubocop:disable Metrics/PerceivedComplexity
      sig { returns(T.nilable(String)) }
      def url_for_relevant_cred
        resolved_url_host = URI(resolved_url).host

        credential_matching_url =
          credentials
          .select { |cred| cred["type"] == "npm_registry" && cred["registry"] }
          .sort_by { |cred| cred.fetch("registry").length }
          .find do |details|
            next true if resolved_url_host == details["registry"]

            uri = if details["registry"]&.include?("://")
                    URI(details.fetch("registry"))
                  else
                    URI("https://#{details['registry']}")
                  end
            resolved_url_host == uri.host && resolved_url.include?(details.fetch("registry"))
          end

        return unless credential_matching_url

        # Trim the resolved URL so that it ends at the same point as the
        # credential registry
        reg = credential_matching_url.fetch("registry")
        resolved_url.gsub(/#{Regexp.quote(reg)}.*/, "") + reg
      end
      # rubocop:enable Metrics/PerceivedComplexity
    end
  end
end
