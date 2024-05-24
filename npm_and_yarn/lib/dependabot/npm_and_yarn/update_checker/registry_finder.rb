# typed: true
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
          http://registry.yarnpkg.com
        ).freeze
        NPM_AUTH_TOKEN_REGEX = %r{//(?<registry>.*)/:_authToken=(?<token>.*)$}
        NPM_GLOBAL_REGISTRY_REGEX = /^registry\s*=\s*['"]?(?<registry>.*?)['"]?$/
        YARN_GLOBAL_REGISTRY_REGEX = /^(?:--)?registry\s+((['"](?<registry>.*)['"])|(?<registry>.*))/
        NPM_SCOPED_REGISTRY_REGEX = /^(?<scope>@[^:]+)\s*:registry\s*=\s*['"]?(?<registry>.*?)['"]?$/
        YARN_SCOPED_REGISTRY_REGEX = /['"](?<scope>@[^:]+):registry['"]\s((['"](?<registry>.*)['"])|(?<registry>.*))/

        def initialize(dependency:, credentials:, npmrc_file: nil,
                       yarnrc_file: nil, yarnrc_yml_file: nil)
          @dependency = dependency
          @credentials = credentials
          @npmrc_file = npmrc_file
          @yarnrc_file = yarnrc_file
          @yarnrc_yml_file = yarnrc_yml_file
        end

        def registry
          @registry ||= locked_registry || configured_registry || first_registry_with_dependency_details
        end

        def auth_headers
          auth_header_for(auth_token)
        end

        def dependency_url
          "#{registry_url}/#{escaped_dependency_name}"
        end

        def tarball_url(version)
          version_without_build_metadata = version.to_s.gsub(/\+.*/, "")

          # Dependency name needs to be unescaped since tarball URLs don't always work with escaped slashes
          "#{registry_url}/#{dependency.name}/-/#{scopeless_name}-#{version_without_build_metadata}.tgz"
        end

        def self.central_registry?(registry)
          CENTRAL_REGISTRIES.any? do |r|
            r.include?(registry)
          end
        end

        def registry_from_rc(dependency_name)
          explicit_registry_from_rc(dependency_name) || global_registry
        end

        private

        attr_reader :dependency
        attr_reader :credentials
        attr_reader :npmrc_file
        attr_reader :yarnrc_file
        attr_reader :yarnrc_yml_file

        def explicit_registry_from_rc(dependency_name)
          if dependency_name.start_with?("@") && dependency_name.include?("/")
            scope = dependency_name.split("/").first
            scoped_registry(scope) || configured_global_registry
          else
            configured_global_registry
          end
        end

        def first_registry_with_dependency_details
          @first_registry_with_dependency_details ||=
            known_registries.find do |details|
              url = "#{details['registry'].gsub(%r{/+$}, '')}/#{escaped_dependency_name}"
              url = "https://#{url}" unless url.start_with?("http")
              response = Dependabot::RegistryClient.get(
                url: url,
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
          url =
            if registry.start_with?("http")
              registry
            else
              protocol =
                if registry_source_url
                  registry_source_url.split("://").first
                else
                  "https"
                end

              "#{protocol}://#{registry}"
            end

          url.gsub(%r{/+$}, "")
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
          known_registries
            .find { |cred| cred["registry"] == registry }
            &.fetch("token", nil)
        end

        def locked_registry
          return unless registry_source_url

          lockfile_registry =
            registry_source_url
            .gsub("https://", "")
            .gsub("http://", "")
          detailed_registry =
            known_registries
            .find { |h| h["registry"].include?(lockfile_registry) }
            &.fetch("registry")

          detailed_registry || lockfile_registry
        end

        def configured_registry
          configured_registry_url = explicit_registry_from_rc(dependency.name)
          return unless configured_registry_url

          normalize_configured_registry(configured_registry_url)
        end

        def known_registries
          @known_registries ||=
            begin
              registries = []
              registries += credentials
                            .select { |cred| cred["type"] == "npm_registry" && cred["registry"] }
                            .tap { |arr| arr.each { |c| c["token"] ||= nil } }
              registries += npmrc_registries
              registries += yarnrc_registries

              unique_registries(registries)
            end
        end

        def npmrc_registries
          return [] unless npmrc_file

          registries = []
          npmrc_file.content.scan(NPM_AUTH_TOKEN_REGEX) do
            next if Regexp.last_match&.[](:registry)&.include?("${")

            registry = T.must(Regexp.last_match)[:registry]
            token = T.must(Regexp.last_match)[:token]&.strip

            registries << {
              "type" => "npm_registry",
              "registry" => registry&.gsub(/\s+/, "%20"),
              "token" => token
            }
          end

          registries += npmrc_global_registries
        end

        def yarnrc_registries
          return [] unless yarnrc_file

          yarnrc_global_registries
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
          return @global_registry if defined? @global_registry

          @global_registry ||= configured_global_registry || "https://registry.npmjs.org"
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def configured_global_registry
          return @configured_global_registry if defined? @configured_global_registry

          @configured_global_registry = (npmrc_file && npmrc_global_registries.first&.fetch("url")) ||
                                        (yarnrc_file && yarnrc_global_registries.first&.fetch("url"))
          return @configured_global_registry if @configured_global_registry

          if parsed_yarnrc_yml&.key?("npmRegistryServer")
            return @configured_global_registry = parsed_yarnrc_yml["npmRegistryServer"]
          end

          replaces_base = credentials.find { |cred| cred["type"] == "npm_registry" && cred.replaces_base? }
          if replaces_base
            registry = replaces_base["registry"]
            registry = "https://#{registry}" unless registry.start_with?("http")
            return @configured_global_registry = registry
          end

          @configured_global_registry = nil
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def npmrc_global_registries
          global_rc_registries(npmrc_file, syntax: NPM_GLOBAL_REGISTRY_REGEX)
        end

        def yarnrc_global_registries
          global_rc_registries(yarnrc_file, syntax: YARN_GLOBAL_REGISTRY_REGEX)
        end

        def scoped_registry(scope)
          scoped_rc_registry = scoped_rc_registry(npmrc_file, syntax: NPM_SCOPED_REGISTRY_REGEX, scope: scope) ||
                               scoped_rc_registry(yarnrc_file, syntax: YARN_SCOPED_REGISTRY_REGEX, scope: scope)
          return scoped_rc_registry if scoped_rc_registry

          if parsed_yarnrc_yml
            yarn_berry_registry = parsed_yarnrc_yml.dig("npmScopes", scope.delete_prefix("@"), "npmRegistryServer")
            return yarn_berry_registry if yarn_berry_registry
          end

          nil
        end

        def global_rc_registries(file, syntax:)
          registries = []

          file.content.scan(syntax) do
            next if Regexp.last_match&.[](:registry)&.include?("${")

            url = T.must(T.must(Regexp.last_match)[:registry]).strip
            registry = normalize_configured_registry(url)
            registries << {
              "type" => "npm_registry",
              "registry" => registry,
              "url" => url,
              "token" => nil
            }
          end

          registries
        end

        def scoped_rc_registry(file, syntax:, scope:)
          file&.content.to_s.scan(syntax) do
            next if Regexp.last_match&.[](:registry)&.include?("${") || Regexp.last_match&.[](:scope) != scope

            return T.must(T.must(Regexp.last_match)[:registry]).strip
          end

          nil
        end

        # npm registries expect slashes to be escaped
        def escaped_dependency_name
          dependency.name.gsub("/", "%2F")
        end

        def scopeless_name
          dependency.name.split("/").last
        end

        def registry_source_url
          sources = dependency.requirements
                              .map { |r| r.fetch(:source) }.uniq.compact
                              .sort_by { |source| self.class.central_registry?(source[:url]) ? 1 : 0 }

          sources.find { |s| s[:type] == "registry" }&.fetch(:url)
        end

        def parsed_yarnrc_yml
          return unless yarnrc_yml_file
          return @parsed_yarnrc_yml if defined? @parsed_yarnrc_yml

          @parsed_yarnrc_yml = YAML.safe_load(yarnrc_yml_file.content)
        end

        def normalize_configured_registry(url)
          url.sub(%r{/+$}, "")
             .sub(%r{^.*?//}, "")
             .gsub(/\s+/, "%20")
        end
      end
    end
  end
end
