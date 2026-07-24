# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/credential"
require "dependabot/github_actions/constants"

module Dependabot
  module GithubActions
    module Lockfile
      # Builds the subprocess environment for the gh-actions-lock engine. Hosted
      # Dependabot is tokenless behind a MITM proxy that overwrites the auth header,
      # while proxyless local runs hold the real github.com token in `credentials`.
      module Env
        extend T::Sig

        # Placeholder satisfies go-gh's "token must be present" check in hosted mode
        # where the proxy supplies real auth. Mirrors git's installation-token username.
        DUMMY_TOKEN = T.let("x-access-token", String)

        sig do
          params(credentials: T::Array[Dependabot::Credential])
            .returns(T::Hash[String, String])
        end
        def self.build(credentials)
          env = {}

          github_credential = github_dot_com_credential(credentials)
          env["GH_TOKEN"] = github_credential&.fetch("password", nil) || DUMMY_TOKEN

          env
        end

        # Mirrors SharedHelpers.configure_git_to_use_https_with_credentials: prefer a
        # deliberately-added token over an app installation token ("v1." prefix).
        sig do
          params(credentials: T::Array[Dependabot::Credential])
            .returns(T.nilable(Dependabot::Credential))
        end
        def self.github_dot_com_credential(credentials)
          candidates = credentials.select do |c|
            c["type"] == "git_source" && c["host"] == GITHUB_COM && c["password"]
          end

          candidates.find { |c| !c["password"]&.start_with?("v1.") } || candidates.first
        end
      end
    end
  end
end
