# typed: strict
# frozen_string_literal: true

require "excon"
require "dependabot/bun/update_checker"
require "dependabot/registry_client"
require "sorbet-runtime"

module Dependabot
  module Bun
    module Package
      class RegistryFinder
        extend T::Sig

        GLOBAL_NPM_REGISTRY = "https://registry.npmjs.org"

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

        sig do
          params(
            dependency: T.nilable(Dependabot::Dependency),
            credentials: T::Array[Dependabot::Credential],
            npmrc_file: T.nilable(Dependabot::DependencyFile),
            yarnrc_file: T.nilable(Dependabot::DependencyFile),
            yarnrc_yml_file: T.nilable(Dependabot::DependencyFile)
          ).void
        end
        def initialize(dependency:, credentials:, npmrc_file: nil,
                       yarnrc_file: nil, yarnrc_yml_file: nil)
          @dependency = dependency
          @credentials = credentials
          @npmrc_file = npmrc_file
          @yarnrc_file = yarnrc_file
          @yarnrc_yml_file = yarnrc_yml_file

          @registry = T.let(nil, T.nilable(String))
          @first_registry_with_dependency_details = T.let(nil, T.nilable(String))
          @known_registries = T.let([], T::Array[T::Hash[String, T.nilable(String)]])
          @configured_global_registry = T.let(nil, T.nilable(String))
          @global_registry = T.let(nil, T.nilable(String))
          @parsed_yarnrc_yml = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        end

        sig { returns(String) }
        def registry
          return @registry if @registry

          @registry = locked_registry || configured_registry || first_registry_with_dependency_details
          T.must(@registry)
        end

        sig { returns(T::Hash[String, String]) }
        def auth_headers
          auth_header_for(auth_token)
        end

        sig { returns(String) }
        def dependency_url
          "#{registry_url}/#{escaped_dependency_name}"
        end

        sig { params(version: T.any(String, Gem::Version)).returns(String) }
        def tarball_url(version)
          version_without_build_metadata = version.to_s.gsub(/\+.*/, "")

          # Dependency name needs to be unescaped since tarball URLs don't always work with escaped slashes
          "#{registry_url}/#{dependency&.name}/-/#{scopeless_name}-#{version_without_build_metadata}.tgz"
        end

        sig { params(registry: String).returns(T::Boolean) }
        def self.central_registry?(registry)
          CENTRAL_REGISTRIES.any? do |r|
            r.include?(registry)
          end
        end

        sig { params(dependency_name: String).returns(T.nilable(String)) }
        def registry_from_rc(dependency_name)
          explicit_registry_from_rc(dependency_name) || global_registry
        end

        sig { returns(T::Boolean) }
        def custom_registry?
          return false if CENTRAL_REGISTRIES.include?(registry_url)

          !(registry_url || "").match?(/registry\.npmjs\.(org|com)/)
        end

        private

        sig { returns(T.nilable(Dependabot::Dependency)) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :npmrc_file
        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :yarnrc_file
        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :yarnrc_yml_file

        sig { params(dependency_name: T.nilable(String)).returns(T.nilable(String)) }
        def explicit_registry_from_rc(dependency_name)
          if dependency_name&.start_with?("@") && dependency_name.include?("/")
            scope = dependency_name.split("/").first
            scoped_registry(T.must(scope)) || configured_global_registry
          else
            configured_global_registry
          end
        end

        sig { returns(T.nilable(String)) }
        def first_registry_with_dependency_details
          return @first_registry_with_dependency_details if @first_registry_with_dependency_details

          @first_registry_with_dependency_details ||=
            known_registries.find do |details|
              url = "#{details['registry']&.gsub(%r{/+$}, '')}/#{escaped_dependency_name}"
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
            rescue URI::InvalidURIError => e
              raise DependencyFileNotResolvable, e.message
            end&.fetch("registry")

          @first_registry_with_dependency_details ||= global_registry.sub(%r{/+$}, "").sub(%r{^.*?//}, "")
        end

        sig { returns(T.nilable(String)) }
        def registry_url
          url =
            if registry.start_with?("http")
              registry
            else
              protocol =
                if registry_source_url
                  registry_source_url&.split("://")&.first
                else
                  "https"
                end

              "#{protocol}://#{registry}"
            end

          url.gsub(%r{/+$}, "")
        end

        sig { params(token: T.nilable(String)).returns(T::Hash[String, String]) }
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

        sig { returns(T.nilable(String)) }
        def auth_token
          known_registries
            .find { |cred| cred["registry"] == registry }
            &.fetch("token", nil)
        end

        sig { returns(T.nilable(String)) }
        def locked_registry
          return unless registry_source_url

          lockfile_registry =
            registry_source_url
            &.gsub("https://", "")
            &.gsub("http://", "")

          if lockfile_registry
            detailed_registry =
              known_registries
              .find { |h| h["registry"]&.include?(lockfile_registry) }
              &.fetch("registry")
          end

          detailed_registry || lockfile_registry
        end

        sig { returns(T.nilable(String)) }
        def configured_registry
          configured_registry_url = explicit_registry_from_rc(dependency&.name)
          return unless configured_registry_url

          normalize_configured_registry(configured_registry_url)
        end

        sig { returns(T::Array[T::Hash[String, T.nilable(String)]]) }
        def known_registries
          return @known_registries if @known_registries.any?

          @known_registries =
            begin
              registries = []
              registries += credentials
                            .select { |cred| cred["type"] == "npm_registry" && cred["registry"] }
                            .tap { |arr| arr.each { |c| c["token"] ||= nil } }
              registries += npmrc_registries
              registries += yarnrc_registries

              unique_registries(registries)
            end
          @known_registries
        end

        sig { returns(T::Array[T::Hash[String, T.nilable(String)]]) }
        def npmrc_registries
          return [] unless npmrc_file

          registries = []
          npmrc_file&.content&.scan(NPM_AUTH_TOKEN_REGEX) do
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

        sig { returns(T::Array[T::Hash[String, T.nilable(String)]]) }
        def yarnrc_registries
          return [] unless yarnrc_file

          yarnrc_global_registries
        end

        sig do
          params(registries: T::Array[T::Hash[String, T.nilable(String)]])
            .returns(T::Array[T::Hash[String, T.nilable(String)]])
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

        sig { returns(String) }
        def global_registry
          return @global_registry if @global_registry

          @global_registry = configured_global_registry || GLOBAL_NPM_REGISTRY
          @global_registry
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { returns(T.nilable(String)) }
        def configured_global_registry
          return @configured_global_registry if @configured_global_registry

          @configured_global_registry = (npmrc_file && npmrc_global_registries.first&.fetch("url")) ||
                                        (yarnrc_file && yarnrc_global_registries.first&.fetch("url"))
          return @configured_global_registry if @configured_global_registry

          if parsed_yarnrc_yml&.key?("npmRegistryServer")
            return @configured_global_registry = T.must(parsed_yarnrc_yml)["npmRegistryServer"]
          end

          replaces_base = credentials.find { |cred| cred["type"] == "npm_registry" && cred.replaces_base? }
          if replaces_base
            registry = replaces_base["registry"]
            registry = "https://#{registry}" unless registry&.start_with?("http")
            return @configured_global_registry = registry
          end

          @configured_global_registry = nil
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(T::Array[T::Hash[String, String]]) }
        def npmrc_global_registries
          global_rc_registries(npmrc_file, syntax: NPM_GLOBAL_REGISTRY_REGEX)
        end

        sig { returns(T::Array[T::Hash[String, String]]) }
        def yarnrc_global_registries
          global_rc_registries(yarnrc_file, syntax: YARN_GLOBAL_REGISTRY_REGEX)
        end

        sig { params(scope: String).returns(T.nilable(String)) }
        def scoped_registry(scope)
          scoped_rc_registry = scoped_rc_registry(npmrc_file, syntax: NPM_SCOPED_REGISTRY_REGEX, scope: scope) ||
                               scoped_rc_registry(yarnrc_file, syntax: YARN_SCOPED_REGISTRY_REGEX, scope: scope)
          return scoped_rc_registry if scoped_rc_registry

          if parsed_yarnrc_yml
            yarn_berry_registry = parsed_yarnrc_yml&.dig("npmScopes", scope.delete_prefix("@"), "npmRegistryServer")
            return yarn_berry_registry if yarn_berry_registry
          end

          nil
        end

        sig do
          params(
            file: T.nilable(Dependabot::DependencyFile),
            syntax: T.any(String, Regexp)
          ).returns(T::Array[T::Hash[String, String]])
        end
        def global_rc_registries(file, syntax:)
          registries = []

          file&.content&.scan(syntax) do
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

        sig do
          params(
            file: T.nilable(Dependabot::DependencyFile),
            syntax: T.any(String, Regexp),
            scope: String
          ).returns(T.nilable(String))
        end
        def scoped_rc_registry(file, syntax:, scope:)
          file&.content.to_s.scan(syntax) do
            next if Regexp.last_match&.[](:registry)&.include?("${") || Regexp.last_match&.[](:scope) != scope

            return T.must(T.must(Regexp.last_match)[:registry]).strip
          end

          nil
        end

        # npm registries expect slashes to be escaped
        sig { returns(T.nilable(String)) }
        def escaped_dependency_name
          dependency&.name&.gsub("/", "%2F")
        end

        sig { returns(T.nilable(String)) }
        def scopeless_name
          dependency&.name&.split("/")&.last
        end

        sig { returns(T.nilable(String)) }
        def registry_source_url # rubocop:disable Metrics/PerceivedComplexity
          sources = dependency&.requirements
                              &.map { |r| r.fetch(:source) }&.uniq&.compact
                              &.sort_by { |source| self.class.central_registry?(source[:url]) ? 1 : 0 }

          sources&.find { |s| s[:type] == "registry" }&.fetch(:url)
        end

        sig { returns(T.nilable(T::Hash[String, T.untyped])) }
        def parsed_yarnrc_yml
          yarnrc_yml_file_content = yarnrc_yml_file&.content
          return unless yarnrc_yml_file_content
          return @parsed_yarnrc_yml if @parsed_yarnrc_yml

          @parsed_yarnrc_yml = YAML.safe_load(yarnrc_yml_file_content)
          @parsed_yarnrc_yml
        end

        sig { params(url: String).returns(String) }
        def normalize_configured_registry(url)
          url.sub(%r{/+$}, "")
             .sub(%r{^.*?//}, "")
             .gsub(/\s+/, "%20")
        end
      end
    end
  end
end
