# frozen_string_literal: true

require "aws-sdk-ecr"
require "base64"

require "dependabot/errors"

module Dependabot
  module Docker
    module Utils
      class CredentialsFinder
        AWS_ECR_URL = /dkr\.ecr\.(?<region>[^.]+)\.amazonaws\.com/

        def initialize(credentials)
          @credentials = credentials
          @registry_details = fetch_registry_info
        end

        def credentials_for_registry(registry_hostname)
          registry_details =
            credentials.
            select { |cred| cred["type"] == "docker_registry" }.
            find { |cred| cred.fetch("registry") == registry_hostname }
          return unless registry_details
          return registry_details unless registry_hostname.match?(AWS_ECR_URL)

          build_aws_credentials(registry_details)
        end

        # Return true if replaces-base is enabled else return false
        def replaces_base?
          return @registry_details["replaces-base"] == true if @registry_details&.key?("replaces-base")
          return false
        end

        def fetch_base_registry
          return @registry_details["registry"] if @registry_details
        end

        private

        def fetch_registry_info
          credentials.
            select { |cred| cred["type"] && cred["replaces-base"] == true }.
            find { |cred| cred.fetch("type") == "docker_registry" }
        end

        attr_reader :credentials

        def build_aws_credentials(registry_details)
          # If credentials have been generated from AWS we can just return them
          return registry_details if registry_details["username"] == "AWS"

          # If we don't have credentials, we might get them from the proxy
          return registry_details if registry_details["username"].nil?

          # Otherwise, we need to use the provided Access Key ID and secret to
          # generate a temporary username and password
          aws_credentials = Aws::Credentials.new(
            registry_details["username"],
            registry_details["password"]
          )

          registry_hostname = registry_details.fetch("registry")
          region = registry_hostname.match(AWS_ECR_URL).
                   named_captures.fetch("region")

          @authorization_tokens ||= {}
          @authorization_tokens[registry_hostname] ||=
            Aws::ECR::Client.new(region: region, credentials: aws_credentials).
            get_authorization_token.authorization_data.first.
            authorization_token

          username, password =
            Base64.decode64(@authorization_tokens[registry_hostname]).split(":")

          registry_details.merge("username" => username, "password" => password)
        rescue Aws::Errors::MissingCredentialsError,
               Aws::ECR::Errors::UnrecognizedClientException,
               Aws::ECR::Errors::InvalidSignatureException
          raise PrivateSourceAuthenticationFailure, registry_hostname
        end
      end
    end
  end
end
