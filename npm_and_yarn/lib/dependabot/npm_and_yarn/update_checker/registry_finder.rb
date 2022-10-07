# frozen_string_literal: true

require "excon"
require "dependabot/npm_and_yarn/update_checker"
require "dependabot/registry_client"

module Dependabot
  module NpmAndYarn
    class UpdateChecker
      class RegistryFinder
        CENTRAL_REGISTRIES = %w(
          https://registry.npmjs.org
          http://registry.npmjs.org
          https://registry.yarnpkg.com
        ).freeze
        NPM_AUTH_TOKEN_REGEX =
          %r{//(?<registry>.*)/:_authToken=(?<token>.*)$}.freeze
        NPM_GLOBAL_REGISTRY_REGEX =
          /^registry\s*=\s*['"]?(?<registry>.*?)['"]?$/.freeze
        YARN_GLOBAL_REGISTRY_REGEX =
          /^(?:--)?registry\s+((['"](?<registry>.*)['"])|(?<registry>.*))/.freeze
        NPM_SCOPED_REGISTRY_REGEX =
          /^(?<scope>@[^:]+)\s*:registry\s*=\s*['"]?(?<registry>.*?)['"]?$/.freeze
        YARN_SCOPED_REGISTRY_REGEX =
          /['"](?<scope>@[^:]+):registry['"]\s((['"](?<registry>.*)['"])|(?<registry>.*))/.freeze

        def initialize(dependency:, credentials:, npmrc_file: nil,
                       yarnrc_file: nil)
          @dependency = dependency
          @credentials = credentials
          @npmrc_file = npmrc_file
          @yarnrc_file = yarnrc_file
        end

        def registry
          locked_registry || first_registry_with_dependency_details
        end

        def auth_headers
          auth_header_for(auth_token)
        end

        def dependency_url
          "#{registry_url.gsub(%r{/+$}, '')}/#{escaped_dependency_name}"
        end

        def self.central_registry?(registry)
          CENTRAL_REGISTRIES.any? do |r|
            r.include?(registry)
          end
        end

        def registry_from_rc(dependency_name)
          return global_registry unless dependency_name.start_with?("@") && dependency_name.include?("/")

          scope = dependency_name.split("/").first
          scoped_registry(scope)
        end

        private

        attr_reader :dependency, :credentials, :npmrc_file, :yarnrc_file

        def first_registry_with_dependency_details
          @first_registry_with_dependency_details ||=
            known_registries.find do |details|
              response = Dependabot::RegistryClient.get(
                url: "https://#{details['registry'].gsub(%r{/+$}, '')}/#{escaped_dependency_name}",
                headers: auth_header_for(details["token"])
              )
              response.status < 400 && JSON.parse(response.body)
            rescue Excon::Error::Timeout,
                   Excon::Error::Socket,
                   JSON::ParserError
              nil
            end&.fetch("registry")

          @first_registry_with_dependency_details ||= global_registry.sub(%r{/+$}, "").sub(%r{^.*?//}, "")
        end

        def registry_url
          protocol =
            if registry_source_url
              registry_source_url.split("://").first
            else
              "https"
            end

          "#{protocol}://#{registry}"
        end

        def auth_header_for(token)
          return {} unless token

          if token.include?(":")
            encoded_token = Base64.encode64(token).delete("\n")
            { "Authorization" => "Basic #{encoded_token}" }
          elsif Base64.decode64(token).ascii_only? &&
                Base64.decode64(token).include?(":")
            { "Authorization" => "Basic #{token.delete("\n")}" }
          else
            { "Authorization" => "Bearer #{token}" }
          end
        end

        def auth_token
          known_registries.
            find { |cred| cred["registry"] == registry }&.
            fetch("token", nil)
        end

        def locked_registry
          return unless registry_source_url

          lockfile_registry =
            registry_source_url.
            gsub("https://", "").
            gsub("http://", "")
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
                            select { |cred| cred["type"] == "npm_registry" }.
                            tap { |arr| arr.each { |c| c["token"] ||= nil } }
              registries += npmrc_registries
              registries += yarnrc_registries

              unique_registries(registries)
            end
        end

        def npmrc_registries
          return [] unless npmrc_file

          registries = []
          npmrc_file.content.scan(NPM_AUTH_TOKEN_REGEX) do
            next if Regexp.last_match[:registry].include?("${")

            registries << {
              "type" => "npm_registry",
              "registry" => Regexp.last_match[:registry],
              "token" => Regexp.last_match[:token]&.strip
            }
          end

          npmrc_file.content.scan(NPM_GLOBAL_REGISTRY_REGEX) do
            next if Regexp.last_match[:registry].include?("${")

            registry = Regexp.last_match[:registry].strip.
                       sub(%r{/+$}, "").
                       sub(%r{^.*?//}, "")
            next if registries.map { |r| r["registry"] }.include?(registry)

            registries << {
              "type" => "npm_registry",
              "registry" => registry,
              "token" => nil
            }
          end

          registries
        end

        def yarnrc_registries
          return [] unless yarnrc_file

          registries = []
          yarnrc_file.content.scan(YARN_GLOBAL_REGISTRY_REGEX) do
            next if Regexp.last_match[:registry].include?("${")

            registry = Regexp.last_match[:registry].strip.
                       sub(%r{/+$}, "").
                       sub(%r{^.*?//}, "")
            registries << {
              "type" => "npm_registry",
              "registry" => registry,
              "token" => nil
            }
          end

          registries
        end

        def unique_registries(registries)
          registries.uniq.reject do |registry|
            next if registry["token"]

            # Reject this entry if an identical one with a token exists
            registries.any? do |r|
              r["token"] && r["registry"] == registry["registry"]
            end
          end
        end

        def global_registry
          npmrc_file&.content.to_s.scan(NPM_GLOBAL_REGISTRY_REGEX) do
            next if Regexp.last_match[:registry].include?("${")

            return Regexp.last_match[:registry].strip
          end

          yarnrc_file&.content.to_s.scan(YARN_GLOBAL_REGISTRY_REGEX) do
            next if Regexp.last_match[:registry].include?("${")

            return Regexp.last_match[:registry].strip
          end

          "https://registry.npmjs.org"
        end

        def scoped_registry(scope)
          npmrc_file&.content.to_s.scan(NPM_SCOPED_REGISTRY_REGEX) do
            next if Regexp.last_match[:registry].include?("${") || Regexp.last_match[:scope] != scope

            return Regexp.last_match[:registry].strip
          end

          yarnrc_file&.content.to_s.scan(YARN_SCOPED_REGISTRY_REGEX) do
            next if Regexp.last_match[:registry].include?("${") || Regexp.last_match[:scope] != scope

            return Regexp.last_match[:registry].strip
          end

          global_registry
        end

        # npm registries expect slashes to be escaped
        def escaped_dependency_name
          dependency.name.gsub("/", "%2F")
        end

        def registry_source_url
          sources = dependency.requirements.
                    map { |r| r.fetch(:source) }.uniq.compact.
                    sort_by { |source| self.class.central_registry?(source[:url]) ? 1 : 0 }

          sources.find { |s| s[:type] == "registry" }&.fetch(:url)
        end
      end
    end
  end
end
