# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/credential"

module Dependabot
  module Gradle
    module Distributions
      extend T::Sig

      DISTRIBUTION_REPOSITORY_URL = "https://services.gradle.org"
      DISTRIBUTION_DEPENDENCY_TYPE = "gradle-distribution"
      DISTRIBUTION_REGISTRY_TYPE = "gradle-distribution"

      sig { params(requirements: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Boolean) }
      def self.distribution_requirements?(requirements)
        requirements.any? do |req|
          req.dig(:source, :type) == DISTRIBUTION_DEPENDENCY_TYPE
        end
      end

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(T.nilable(Dependabot::Credential)) }
      def self.find_credential(credentials)
        credentials.find { |cred| cred["type"] == DISTRIBUTION_REGISTRY_TYPE }
      end

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(String) }
      def self.distribution_url(credentials)
        credential = find_credential(credentials)
        return DISTRIBUTION_REPOSITORY_URL unless credential

        T.must(credential["url"]).gsub(%r{/+$}, "")
      end

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(T::Hash[String, String]) }
      def self.auth_headers_for(credentials)
        credential = find_credential(credentials)
        return {} unless credential

        username = credential["username"]
        password = credential["password"]
        return {} unless username && password

        token = Base64.strict_encode64("#{username}:#{password}")
        { "Authorization" => "Basic #{token}" }
      end
    end
  end
end
