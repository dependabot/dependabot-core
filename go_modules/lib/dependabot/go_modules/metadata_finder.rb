# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"

module Dependabot
  module GoModules
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      PKG_GO_DEV_MODULE_API = "https://pkg.go.dev/v1/module"

      # pkg.go.dev reports golang.org/x modules as documented on cs.opensource.google.
      # Convert all golang.org/x paths to their corresponding GitHub mirror URLs.
      GOLANG_X_MODULE = %r{\Agolang\.org/x/(?<repo>[\w.-]+)}
      GOLANG_MIRROR_URL = "https://github.com/golang"

      private

      sig { override.returns(T.nilable(Source)) }
      def look_up_source
        url = golang_x_mirror_url || pkg_go_dev_repo_url
        Source.from_url(url) if url
      end

      sig { returns(T.nilable(String)) }
      def golang_x_mirror_url
        match_data = GOLANG_X_MODULE.match(dependency.name)
        return nil unless match_data

        "#{GOLANG_MIRROR_URL}/#{match_data[:repo]}"
      end

      sig { returns(T.nilable(String)) }
      def pkg_go_dev_repo_url
        response = Dependabot::RegistryClient.get(url: "#{PKG_GO_DEV_MODULE_API}/#{dependency.name}")
        return nil unless response.status == 200

        repo_url = T.cast(JSON.parse(response.body), T::Hash[String, Object])["repoUrl"]
        repo_url if repo_url.is_a?(String)
      rescue JSON::ParserError, Excon::Error
        nil
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("go_modules", Dependabot::GoModules::MetadataFinder)
