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

        return T.must(url_base.gsub("%2F", "/").split("/").last) unless package_name

        "#{package_name}#{T.must(url_base.gsub('%2F', '/').split('/').last)}"
      end

      private

      sig { returns(String) }
      attr_reader :resolved_url

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T.nilable(String)) }
      def url_for_relevant_cred
        resolved_uri = URI(resolved_url)

        credential_matching_url =
          credentials
          .select { |cred| cred["type"] == "npm_registry" && cred["registry"] }
          .sort_by { |cred| cred.fetch("registry").length }
          .find { |details| credential_matches?(details, resolved_uri: resolved_uri) }

        return unless credential_matching_url

        reg = credential_matching_url.fetch("registry")
        # When the credential registry already includes an explicit scheme, return
        # it directly — the gsub pattern would not match and would produce a
        # malformed string if it ran.
        return reg if reg.include?("://")

        build_registry_url(registry: reg, resolved_uri: resolved_uri)
      end

      sig { params(registry: String, resolved_uri: URI::Generic).returns(String) }
      def build_registry_url(registry:, resolved_uri:)
        credential_uri = URI("https://#{registry}")
        normalized_path = credential_uri.path.to_s.chomp("/")

        "#{resolved_uri.scheme}://#{resolved_uri.authority}#{normalized_path}"
      end

      # Enforce npm registry credential boundaries by matching on host, optional
      # explicit scheme, and full path segments so sibling paths on the same host
      # cannot inherit credentials configured for a different registry scope.
      sig { params(details: Dependabot::Credential, resolved_uri: URI::Generic).returns(T::Boolean) }
      def credential_matches?(details, resolved_uri:)
        resolved_url_host = resolved_uri.host
        return true if resolved_url_host == details["registry"]

        registry_has_scheme = details["registry"]&.include?("://")
        uri = if registry_has_scheme
                URI(details.fetch("registry"))
              else
                URI("https://#{details['registry']}")
              end
        return false unless resolved_url_host == uri.host
        # When the credential includes an explicit scheme, require scheme
        # equality so we do not attribute a URL to credentials configured for
        # a different transport protocol.
        return false if registry_has_scheme && resolved_uri.scheme != uri.scheme

        # Use path-segment-aware matching to prevent credentials configured
        # for one path-scoped registry from being applied to sibling paths
        # on the same host (e.g., /victim-npm should not match /victim-npm-evil).
        credential_path_match?(uri: uri, resolved_url_path: resolved_uri.path.to_s)
      end

      sig { params(uri: URI::Generic, resolved_url_path: String).returns(T::Boolean) }
      def credential_path_match?(uri:, resolved_url_path:)
        registry_path = uri.path.to_s.chomp("/")
        registry_path.empty? ||
          resolved_url_path.start_with?("#{registry_path}/") ||
          resolved_url_path == registry_path
      end
    end
  end
end
