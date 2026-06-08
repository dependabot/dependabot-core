# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Bun
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

        return T.must(url_base.gsub("%2F", "/").split("/").last) unless package_name

        "#{package_name}#{T.must(url_base.gsub('%2F', '/').split('/').last)}"
      end

      private

      sig { returns(String) }
      attr_reader :resolved_url

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      # rubocop:disable Metrics/PerceivedComplexity
      sig { returns(T.nilable(String)) }
      def url_for_relevant_cred
        resolved_uri = URI(resolved_url)
        resolved_url_host = resolved_uri.host
        resolved_url_path = resolved_uri.path.to_s

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
            next false unless resolved_url_host == uri.host

            # Use path-segment-aware matching to prevent credentials configured
            # for one path-scoped registry from being applied to sibling paths
            # on the same host (e.g., /victim-npm should not match /victim-npm-evil).
            credential_path_match?(uri: uri, resolved_url_path: resolved_url_path)
          end

        return unless credential_matching_url

        # Trim the resolved URL so that it ends at the same point as the
        # credential registry
        reg = credential_matching_url.fetch("registry")
        resolved_url.gsub(/#{Regexp.quote(reg)}.*/, "") + reg
      end

      sig { params(uri: URI::Generic, resolved_url_path: String).returns(T::Boolean) }
      def credential_path_match?(uri:, resolved_url_path:)
        registry_path = uri.path.to_s.chomp("/")
        registry_path.empty? ||
          resolved_url_path.start_with?("#{registry_path}/") ||
          resolved_url_path == registry_path
      end
      # rubocop:enable Metrics/PerceivedComplexity
    end
  end
end
