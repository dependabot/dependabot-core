# typed: strict
# frozen_string_literal: true

require "excon"

module Dependabot
  module Javascript
    module Shared
      module UpdateChecker
        class RegistryFinder
          extend T::Sig

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

          Registry = T.type_alias { String }
          RegistrySyntax = T.type_alias { T.any(Regexp, String) }

          sig do
            params(
              dependency: T.nilable(Dependency),
              credentials: T::Array[Credential],
              rc_file: T.nilable(DependencyFile)
            ).void
          end
          def initialize(dependency:, credentials:, rc_file:)
            @dependency = dependency
            @credentials = credentials
            @rc_file = rc_file

            @npmrc_file = T.let(
              rc_file&.name&.end_with?(".npmrc") ? rc_file : nil,
              T.nilable(DependencyFile)
            )
          end

          sig { returns(T.nilable(Registry)) }
          def registry
            @registry ||= T.let(
              locked_registry || configured_registry || first_registry_with_dependency_details,
              T.nilable(Registry)
            )
          end

          sig { returns(T::Hash[String, String]) }
          def auth_headers
            auth_header_for(auth_token)
          end

          sig { returns(String) }
          def dependency_url
            "#{registry_url}/#{escaped_dependency_name}"
          end

          sig { params(version: Version).returns(String) }
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

          private

          sig { returns(T.nilable(Dependency)) }
          attr_reader :dependency

          sig { returns(T::Array[Credential]) }
          attr_reader :credentials

          sig { returns(T.nilable(DependencyFile)) }
          attr_reader :rc_file

          sig { returns(T.nilable(DependencyFile)) }
          attr_reader :npmrc_file

          sig { params(dependency_name: T.nilable(String)).returns(T.nilable(String)) }
          def explicit_registry_from_rc(dependency_name)
            if dependency_name&.start_with?("@") && dependency_name.include?("/")
              scope = dependency_name.split("/").first
              scoped_registry(scope) || configured_global_registry
            else
              configured_global_registry
            end
          end

          sig { returns(T.nilable(Registry)) }
          def first_registry_with_dependency_details
            @first_registry_with_dependency_details ||= T.let(
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
              rescue URI::InvalidURIError => e
                raise DependencyFileNotResolvable, e.message
              end&.fetch("registry"),
              T.nilable(Registry)
            )

            @first_registry_with_dependency_details ||= global_registry.to_s.sub(%r{/+$}, "").sub(%r{^.*?//}, "")
          end

          sig { returns(T.nilable(String)) }
          def registry_url
            url =
              if registry&.start_with?("http")
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

            url&.gsub(%r{/+$}, "")
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

          sig { returns(T.nilable(Registry)) }
          def locked_registry
            return unless registry_source_url

            lockfile_registry =
              T.must(registry_source_url)
               .gsub("https://", "")
               .gsub("http://", "")
            detailed_registry =
              known_registries
              .find { |h| h["registry"].include?(lockfile_registry) }
              &.fetch("registry")

            detailed_registry || lockfile_registry
          end

          sig { returns(T.nilable(String)) }
          def configured_registry
            configured_registry_url = explicit_registry_from_rc(dependency&.name)
            return unless configured_registry_url

            normalize_configured_registry(configured_registry_url)
          end

          sig { returns(T::Array[T::Hash[String, T.untyped]]) }
          def known_registries
            @known_registries ||= T.let(
              begin
                registries = []
                registries += credentials
                              .select { |cred| cred["type"] == "npm_registry" && cred["registry"] }
                              .tap { |arr| arr.each { |c| c["token"] ||= nil } }
                registries += npmrc_registries

                unique_registries(registries)
              end,
              T.nilable(T::Array[T::Hash[String, T.untyped]])
            )
          end

          sig { returns(T::Array[T::Hash[String, T.untyped]]) }
          def npmrc_registries
            return [] unless npmrc_file

            registries = []
            T.must(npmrc_file).content&.scan(NPM_AUTH_TOKEN_REGEX) do
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

          sig { params(registries: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
          def unique_registries(registries)
            registries.uniq.reject do |registry|
              next if registry["token"]

              # Reject this entry if an identical one with a token exists
              registries.any? do |r|
                r["token"] && r["registry"] == registry["registry"]
              end
            end
          end

          sig { returns(T.nilable(String)) }
          def global_registry
            return @global_registry if defined? @global_registry

            @global_registry ||= T.let(configured_global_registry || "https://registry.npmjs.org", T.nilable(String))
          end

          sig { returns(T.nilable(String)) }
          def configured_global_registry
            return @configured_global_registry if defined? @configured_global_registry

            @configured_global_registry = T.let(
              npmrc_file && npmrc_global_registries.first&.fetch("url"),
              T.nilable(String)
            )
            return @configured_global_registry if @configured_global_registry

            replaces_base = credentials.find { |cred| cred["type"] == "npm_registry" && cred.replaces_base? }
            if replaces_base
              registry = replaces_base["registry"]
              registry = "https://#{registry}" unless registry&.start_with?("http")
              return @configured_global_registry = registry
            end

            @configured_global_registry = nil
          end

          sig { returns(T::Array[T::Hash[String, T.nilable(String)]]) }
          def npmrc_global_registries
            return [] unless npmrc_file

            global_rc_registries(T.must(npmrc_file), syntax: NPM_GLOBAL_REGISTRY_REGEX)
          end

          sig { params(scope: T.nilable(String)).returns(T.nilable(String)) }
          def scoped_registry(scope)
            scoped_rc_registry(npmrc_file, syntax: NPM_SCOPED_REGISTRY_REGEX, scope: scope)
          end

          sig do
            params(file: DependencyFile, syntax: RegistrySyntax)
              .returns(T::Array[T::Hash[String, T.nilable(String)]])
          end
          def global_rc_registries(file, syntax:)
            registries = []

            file.content&.scan(syntax) do
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
            params(file: T.nilable(DependencyFile), syntax: RegistrySyntax, scope: T.nilable(String))
              .returns(T.nilable(String))
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
            return unless dependency

            T.must(dependency).name.gsub("/", "%2F")
          end

          sig { returns(T.nilable(String)) }
          def scopeless_name
            return unless dependency

            T.must(dependency).name.split("/").last
          end

          sig { returns(T.nilable(String)) }
          def registry_source_url
            return unless dependency

            sources = T.must(dependency).requirements
                       .map { |r| r.fetch(:source) }.uniq.compact
                       .sort_by { |source| self.class.central_registry?(source[:url]) ? 1 : 0 }

            sources.find { |s| s[:type] == "registry" }&.fetch(:url)
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
end
