# typed: strict
# frozen_string_literal: true

require "aws-sdk-ecr"
require "base64"
require "sorbet-runtime"

require "dependabot/credential"
require "dependabot/errors"

module Dependabot
  module Docker
    module Utils
      class CredentialsFinder
        extend T::Sig

        AWS_ECR_URL = /dkr\.ecr\.(?<region>[^.]+)\.amazonaws\.com/
        DEFAULT_DOCKER_HUB_REGISTRY = "registry.hub.docker.com"

        sig { params(credentials: T::Array[Dependabot::Credential]).void }
        def initialize(credentials)
          @credentials = credentials
        end

        sig { params(registry_hostname: T.nilable(String)).returns(T.nilable(Dependabot::Credential)) }
        def credentials_for_registry(registry_hostname)
          registry_details =
            credentials
            .select { |cred| cred["type"] == "docker_registry" }
            .find { |cred| cred.fetch("registry") == registry_hostname }
          return unless registry_details
          return registry_details unless registry_hostname&.match?(AWS_ECR_URL)

          build_aws_credentials(registry_details)
        end

        sig { returns(T.nilable(String)) }
        def base_registry
          @base_registry ||= T.let(
            credentials.find do |cred|
              cred["type"] == "docker_registry" && cred.replaces_base?
            end,
            T.nilable(Dependabot::Credential)
          )
          @base_registry ||= Dependabot::Credential.new({ "registry" => DEFAULT_DOCKER_HUB_REGISTRY,
                                                          "credentials" => nil })
          @base_registry["registry"]
        end

        sig { params(registry: String).returns(T::Boolean) }
        def using_dockerhub?(registry)
          registry == DEFAULT_DOCKER_HUB_REGISTRY
        end

        private

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { params(registry_details: Dependabot::Credential).returns(Dependabot::Credential) }
        def build_aws_credentials(registry_details)
          # If credentials have been generated from AWS we can just return them
          return registry_details if registry_details["username"] == "AWS"

          # Build a client either with explicit creds or default creds
          registry_hostname = registry_details.fetch("registry")
          region = registry_hostname.match(AWS_ECR_URL).named_captures.fetch("region")
          aws_credentials = Aws::Credentials.new(
            registry_details["username"],
            registry_details["password"]
          )

          ecr_client =
            if aws_credentials.set?
              Aws::ECR::Client.new(region: region, credentials: aws_credentials)
            else
              # Let the client check default locations for credentials
              Aws::ECR::Client.new(region: region)
            end

          # If the client still lacks credentials, we might be running within GitHub's
          # Dependabot Service, in which case we might get them from the proxy
          return registry_details if ecr_client.config.credentials.nil?

          # Otherwise, we need to use the provided Access Key ID and secret to
          # generate a temporary username and password
          @authorization_tokens ||= T.let({}, T.nilable(T::Hash[String, String]))
          @authorization_tokens[registry_hostname] ||=
            ecr_client.get_authorization_token.authorization_data.first.authorization_token
          username, password =
            Base64.decode64(T.must(@authorization_tokens[registry_hostname])).split(":")
          registry_details.merge(Dependabot::Credential.new({ "username" => username, "password" => password }))
        rescue Aws::Errors::MissingCredentialsError,
               Aws::ECR::Errors::UnrecognizedClientException,
               Aws::ECR::Errors::InvalidSignatureException
          raise PrivateSourceAuthenticationFailure, registry_hostname
        end
      end
    end
  end
end
