# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/registry_client"

module Dependabot
  module GoModules
    module PathConverter
      extend T::Sig

      PKG_GO_DEV_MODULE_API = "https://pkg.go.dev/v1/module"

      # pkg.go.dev reports golang.org/x modules as documented on cs.opensource.google.
      # Convert all `golang.org/x` paths to their corresponding GitHub mirror URLs.
      GOLANG_X_MODULE = %r{\Agolang\.org/x/(?<repo>[\w.-]+)}
      GOLANG_MIRROR_URL = "https://github.com/golang"

      sig { params(path: String).returns(T.nilable(String)) }
      def self.git_url_for_path(path)
        golang_x_mirror_url(path) || pkg_go_dev_repo_url(path)
      end

      sig { params(path: String).returns(T.nilable(String)) }
      private_class_method def self.golang_x_mirror_url(path)
        match_data = GOLANG_X_MODULE.match(path)
        return nil unless match_data

        "#{GOLANG_MIRROR_URL}/#{match_data[:repo]}"
      end

      sig { params(path: String).returns(T.nilable(String)) }
      private_class_method def self.pkg_go_dev_repo_url(path)
        response = Dependabot::RegistryClient.get(url: "#{PKG_GO_DEV_MODULE_API}/#{path}")
        return nil unless response.status == 200

        module_details = T.cast(JSON.parse(response.body), T::Hash[String, T.anything])
        T.cast(module_details["repoUrl"], T.nilable(String))
      rescue JSON::ParserError, TypeError, Excon::Error::Timeout, Excon::Error::Socket
        nil
      end
    end
  end
end
