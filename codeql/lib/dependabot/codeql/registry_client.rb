# typed: strict
# frozen_string_literal: true

require "cgi"
require "excon"
require "json"
require "time"
require "docker_registry2"
require "sorbet-runtime"

require "dependabot/credential"
require "dependabot/errors"
require "dependabot/logger"

module Dependabot
  module Codeql
    # Thin GHCR OCI client used to list the published versions (tags) of a
    # CodeQL pack. CodeQL packs are published to the GitHub Container Registry
    # as OCI artifacts addressed as `<scope>/<pack>`, so listing their tags is
    # the same OCI Distribution `tags/list` call the docker ecosystem makes.
    class RegistryClient
      extend T::Sig

      REGISTRY_HOST = "ghcr.io"
      CREDENTIAL_TYPE = "docker_registry"
      PACKAGES_API_HOST = "https://api.github.com"
      PROXY_ENV_KEYS = %w(HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy).freeze

      sig { params(credentials: T::Array[Dependabot::Credential]).void }
      def initialize(credentials:)
        @credentials = credentials
      end

      sig { params(pack_name: String).returns(T::Array[String]) }
      def tags(pack_name)
        tags_with_client(client, pack_name)
      rescue DockerRegistry2::RegistryAuthenticationException,
             DockerRegistry2::RegistryAuthorizationException
        anonymous_tags(pack_name)
      rescue DockerRegistry2::RegistryUnknownException, Timeout::Error
        raise Dependabot::PrivateSourceTimedOut, REGISTRY_HOST
      rescue DockerRegistry2::RegistryHTTPException => e
        raise Dependabot::PrivateSourceBadResponse.new(REGISTRY_HOST, e.message)
      end

      # Best-effort map of version tag => publish time, sourced from the GitHub
      # Packages API. Returns an empty hash when the metadata is unavailable so
      # cooldown filtering degrades gracefully instead of blocking updates.
      sig { params(pack_name: String).returns(T::Hash[String, Time]) }
      def release_dates(pack_name)
        org, package = pack_name.split("/", 2)
        return {} if org.nil? || package.nil? || package.empty?

        url = "#{PACKAGES_API_HOST}/orgs/#{org}/packages/container/#{CGI.escape(package)}/versions?per_page=100"
        response = Excon.get(url, headers: github_headers, idempotent: true)
        return {} unless response.status == 200

        parse_release_dates(response.body)
      rescue StandardError => e
        Dependabot.logger.warn("Could not fetch release dates for #{pack_name} from GHCR: #{e.message}")
        {}
      end

      private

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { params(pack_name: String).returns(T::Array[String]) }
      def anonymous_tags(pack_name)
        previous_proxy_env = PROXY_ENV_KEYS.to_h { |key| [key, ENV.fetch(key, nil)] }
        PROXY_ENV_KEYS.each { |key| ENV.delete(key) }
        @anonymous_client = nil

        tags_with_client(anonymous_client, pack_name)
      rescue DockerRegistry2::RegistryAuthenticationException,
             DockerRegistry2::RegistryAuthorizationException
        raise Dependabot::PrivateSourceAuthenticationFailure, REGISTRY_HOST
      ensure
        previous_proxy_env&.each do |key, value|
          value.nil? ? ENV.delete(key) : ENV[key] = value
        end
        @anonymous_client = nil
      end

      sig { params(registry: DockerRegistry2::Registry, pack_name: String).returns(T::Array[String]) }
      def tags_with_client(registry, pack_name)
        tags = registry.tags(pack_name, auto_paginate: true).fetch("tags", [])
        return [] unless tags.is_a?(Array)

        tags.grep(String)
      end

      sig { params(body: String).returns(T::Hash[String, Time]) }
      def parse_release_dates(body)
        versions = JSON.parse(body)
        return {} unless versions.is_a?(Array)

        versions.each_with_object({}) do |version, acc|
          created = version["created_at"]
          next unless created.is_a?(String)

          tags = version.dig("metadata", "container", "tags")
          next unless tags.is_a?(Array)

          published_at = Time.parse(created)
          tags.each { |tag| acc[tag.to_s] = published_at }
        end
      end

      sig { returns(T::Hash[String, String]) }
      def github_headers
        headers = { "Accept" => "application/vnd.github+json" }
        token = github_token
        headers["Authorization"] = "Bearer #{token}" if token
        headers
      end

      sig { returns(T.nilable(String)) }
      def github_token
        credentials
          .select { |cred| cred["type"] == "git_source" && cred["host"] == "github.com" }
          .filter_map { |cred| cred["password"] }
          .first
      end

      sig { returns(DockerRegistry2::Registry) }
      def client
        @client ||= T.let(
          DockerRegistry2::Registry.new(
            "https://#{REGISTRY_HOST}",
            user: registry_credential&.fetch("username", nil),
            password: registry_credential&.fetch("password", nil),
            http_options: { proxy: ENV.fetch("HTTPS_PROXY", nil) }
          ),
          T.nilable(DockerRegistry2::Registry)
        )
      end

      sig { returns(DockerRegistry2::Registry) }
      def anonymous_client
        @anonymous_client ||= T.let(
          DockerRegistry2::Registry.new(
            "https://#{REGISTRY_HOST}"
          ),
          T.nilable(DockerRegistry2::Registry)
        )
      end

      sig { returns(T.nilable(Dependabot::Credential)) }
      def registry_credential
        @registry_credential ||= T.let(
          credentials
            .select { |cred| cred["type"] == CREDENTIAL_TYPE }
            .find do |cred|
              password = cred["password"]
              cred["registry"] == REGISTRY_HOST && password.is_a?(String) && !password.strip.empty?
            end,
          T.nilable(Dependabot::Credential)
        )
      end
    end
  end
end
