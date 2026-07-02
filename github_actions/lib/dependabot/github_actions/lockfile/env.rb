# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/credential"
require "dependabot/github_actions/constants"

module Dependabot
  module GithubActions
    module Lockfile
      # Builds the subprocess environment for the gh-actions-pin engine. Two runtimes:
      # hosted Dependabot is tokenless behind a MITM proxy that overwrites the auth
      # header, so we pass a non-empty placeholder (go-gh refuses an empty token);
      # proxyless (local dry-run, some GHES) holds the real token in `credentials`.
      # Either way we never log the token. Proxy/CA transport vars are inherited.
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

          ghes = ghes_credential(credentials)
          if ghes
            env["GH_HOST"] = T.must(ghes["host"])
            env["GH_ENTERPRISE_TOKEN"] = T.must(ghes["password"])
          end

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

        sig do
          params(credentials: T::Array[Dependabot::Credential])
            .returns(T.nilable(Dependabot::Credential))
        end
        def self.ghes_credential(credentials)
          credentials.find do |c|
            c["type"] == "git_source" && c["host"] != GITHUB_COM && c["host"] && c["password"]
          end
        end
      end
    end
  end
end
