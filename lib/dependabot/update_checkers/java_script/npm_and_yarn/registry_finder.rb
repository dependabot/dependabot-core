# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/java_script/npm_and_yarn"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class NpmAndYarn
        class RegistryFinder
          AUTH_TOKEN_REGEX = %r{//(?<registry>.*)/:_authToken=(?<token>.*)$}

          def initialize(dependency:, credentials:, npmrc_file: nil)
            @dependency = dependency
            @credentials = credentials
            @npmrc_file = npmrc_file
          end

          def registry
            locked_registry || first_registry_with_dependency_details
          end

          def auth_headers
            auth_header_for(auth_token)
          end

          def dependency_url
            "#{registry_url}/#{escaped_dependency_name}"
          end

          private

          attr_reader :dependency, :credentials, :npmrc_file

          def first_registry_with_dependency_details
            @first_registry_with_dependency_details ||=
              known_registries.find do |details|
                Excon.get(
                  "https://#{details['registry'].gsub(%r{/+$}, '')}/"\
                  "#{escaped_dependency_name}",
                  headers: auth_header_for(details["token"]),
                  connect_timeout: 5,
                  write_timeout: 5,
                  read_timeout: 5,
                  idempotent: true,
                  omit_default_port: true,
                  middlewares: SharedHelpers.excon_middleware
                ).status < 400
              rescue Excon::Error::Timeout, Excon::Error::Socket
                nil
              end&.fetch("registry")

            @first_registry_with_dependency_details ||= "registry.npmjs.org"
          end

          def registry_url
            protocol =
              if dependency_source&.fetch(:type) == "private_registry"
                dependency_source.fetch(:url).split("://").first
              else
                "https"
              end

            "#{protocol}://#{registry}"
          end

          def auth_header_for(token)
            return {} unless token

            if token.include?(":")
              encoded_token = Base64.encode64(token).chomp.delete("\n")
              { "Authorization" => "Basic #{encoded_token}" }
            else
              { "Authorization" => "Bearer #{token}" }
            end
          end

          def auth_token
            known_registries.
              find { |cred| cred["registry"] == registry }&.
              fetch("token")
          end

          def locked_registry
            source = dependency_source
            return unless source
            return unless source.fetch(:type) == "private_registry"

            lockfile_registry =
              source.fetch(:url).gsub("https://", "").gsub("http://", "")
            detailed_registry =
              known_registries.
              find { |h| h["registry"].include?(lockfile_registry) }&.
              fetch("registry")

            detailed_registry || lockfile_registry
          end

          def known_registries
            @known_registries ||=
              begin
                registries = []
                registries += credentials.
                              select { |cred| cred["type"] == "npm_registry" }

                npmrc_file&.content.to_s.scan(AUTH_TOKEN_REGEX) do
                  registries << {
                    "type" => "npm_registry",
                    "registry" => Regexp.last_match[:registry],
                    "token" => Regexp.last_match[:token]
                  }
                end

                registries.uniq
              end
          end

          # npm registries expect slashes to be escaped
          def escaped_dependency_name
            dependency.name.gsub("/", "%2F")
          end

          def dependency_source
            sources = dependency.requirements.
                      map { |r| r.fetch(:source) }.uniq.compact
            return sources.first unless sources.count > 1
            raise "Multiple sources! #{sources.join(', ')}"
          end
        end
      end
    end
  end
end
