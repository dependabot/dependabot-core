# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Maven
    module Utils
      class AuthHeadersFinder
        extend T::Sig

        sig { params(credentials: T::Array[Dependabot::Credential]).void }
        def initialize(credentials)
          @credentials = credentials
        end

        sig { params(maven_repo_url: String).returns(T::Hash[String, String]) }
        def auth_headers(maven_repo_url)
          cred =
            credentials.select { |c| c["type"] == "maven_repository" }
                       .find do |c|
              cred_url = c.fetch("url").gsub(%r{/+$}, "")
              next false unless cred_url == maven_repo_url

              c.fetch("username", nil)
            end

          return gitlab_auth_headers(maven_repo_url) unless cred

          token = cred.fetch("username") + ":" + cred.fetch("password")
          encoded_token = Base64.strict_encode64(token)
          { "Authorization" => "Basic #{encoded_token}" }
        end

        private

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { params(maven_repo_url: T.any(URI::Generic, String)).returns(T::Hash[T.untyped, T.untyped]) }
        def gitlab_auth_headers(maven_repo_url)
          return {} unless gitlab_maven_repo?(T.must(URI(maven_repo_url).path))

          cred =
            credentials.select { |c| c["type"] == "git_source" }
                       .find do |c|
              cred_host = c.fetch("host").gsub(%r{/+$}, "")
              next false unless URI(maven_repo_url).host == cred_host

              c.fetch("password", nil)
            end

          return {} unless cred

          { "Private-Token" => cred.fetch("password") }
        end

        sig { params(maven_repo_path: String).returns(T::Boolean) }
        def gitlab_maven_repo?(maven_repo_path)
          gitlab_maven_repo_reg = %r{^/api/v4.*/packages/maven/?$}
          maven_repo_path.match?(gitlab_maven_repo_reg)
        end
      end
    end
  end
end
