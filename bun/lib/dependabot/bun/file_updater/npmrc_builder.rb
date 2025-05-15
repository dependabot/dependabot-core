# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/bun/file_updater"

module Dependabot
  module Bun
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Build a .npmrc file from the lockfile content, credentials, and any
      # committed .npmrc
      # We should refactor this to use Package::RegistryFinder
      class NpmrcBuilder
        extend T::Sig

        CENTRAL_REGISTRIES = T.let(%w(registry.npmjs.org).freeze, T::Array[String])

        SCOPED_REGISTRY = /^\s*@(?<scope>\S+):registry\s*=\s*(?<registry>\S+)/

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            dependencies: T::Array[Dependabot::Dependency]
          ).void
        end
        def initialize(dependency_files:, credentials:, dependencies: [])
          @dependency_files = dependency_files
          @credentials = credentials
          @dependencies = dependencies
        end

        # PROXY WORK
        sig { returns(String) }
        def npmrc_content
          initial_content =
            if npmrc_file then complete_npmrc_from_credentials
            else
              build_npmrc_content_from_lockfile
            end

          final_content = initial_content || ""

          return final_content unless registry_credentials.any?

          credential_lines_for_npmrc.each do |credential_line|
            next if final_content.include?(credential_line)

            final_content = [final_content, credential_line].reject(&:empty?).join("\n")
          end

          final_content
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T.nilable(String)) }
        def build_npmrc_content_from_lockfile
          return unless global_registry

          registry = T.must(global_registry)["registry"]
          registry = "https://#{registry}" unless registry&.start_with?("http")
          "registry = #{registry}\n" \
            "#{npmrc_global_registry_auth_line}" \
            "always-auth = true"
        end

        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/CyclomaticComplexity
        sig { returns(T.nilable(Dependabot::Credential)) }
        def global_registry
          return @global_registry if defined?(@global_registry)

          @global_registry = T.let(
            registry_credentials.find do |cred|
              next false if CENTRAL_REGISTRIES.include?(cred["registry"])

              # If all the URLs include this registry, it's global
              next true if dependency_urls&.size&.positive? && dependency_urls&.all? do |url|
                             url.include?(T.must(cred["registry"]))
                           end

              # Check if this registry has already been defined in .npmrc as a scoped registry
              next false if npmrc_scoped_registries&.any? { |sr| sr.include?(T.must(cred["registry"])) }

              # If any unscoped URLs include this registry, assume it's global
              dependency_urls
                &.reject { |u| u.include?("@") || u.include?("%40") }
                &.any? { |url| url.include?(T.must(cred["registry"])) }
            end,
            T.nilable(Dependabot::Credential)
          )
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/CyclomaticComplexity
        sig { returns(String) }
        def npmrc_global_registry_auth_line
          # This token is passed in from the Dependabot Config
          # We write it to the .npmrc file so that it can be used by the VulnerabilityAuditor
          token = global_registry&.fetch("token", nil)
          return "" unless token

          auth_line(token, global_registry&.fetch("registry")) + "\n"
        end

        sig { returns(T.nilable(T::Array[String])) }
        def dependency_urls
          return @dependency_urls if defined?(@dependency_urls)

          @dependency_urls = []

          if dependencies.any?
            @dependency_urls = dependencies.map do |dependency|
              Package::RegistryFinder.new(
                dependency: dependency,
                credentials: credentials,
                npmrc_file: npmrc_file
              ).dependency_url
            end
            return @dependency_urls
          end

          # The registry URL for Bintray goes into the lockfile in a
          # modified format, so we modify it back before checking against
          # our credentials
          @dependency_urls = T.let(
            @dependency_urls.map do |url|
              url.gsub("dl.bintray.com//", "api.bintray.com/npm/")
            end,
            T.nilable(T::Array[String])
          )
        end
        sig { returns(String) }
        def complete_npmrc_from_credentials
          # removes attribute timeout to allow for job update,
          # having a timeout=xxxxx value is causing some jobs to fail
          initial_content = T.must(T.must(npmrc_file).content)
                             .gsub(/^.*\$\{.*\}.*/, "").strip.gsub(/^timeout.*/, "").strip + "\n"

          return initial_content unless global_registry

          registry = T.must(global_registry)["registry"]
          registry = "https://#{registry}" unless registry&.start_with?("http")
          initial_content +
            "registry = #{registry}\n" \
            "#{npmrc_global_registry_auth_line}" \
            "always-auth = true\n"
        end

        sig { returns(T::Array[String]) }
        def credential_lines_for_npmrc
          lines = T.let([], T::Array[String])
          registry_credentials.each do |cred|
            registry = cred.fetch("registry")

            lines += T.must(registry_scopes(registry)) if registry_scopes(registry)

            token = cred.fetch("token", nil)
            next unless token

            lines << auth_line(token, registry)
          end

          return lines unless lines.any? { |str| str.include?("auth=") }

          # Work around a suspected yarn bug
          ["always-auth = true"] + lines
        end

        sig { params(token: String, registry: T.nilable(String)).returns(String) }
        def auth_line(token, registry = nil)
          auth = if token.include?(":")
                   encoded_token = Base64.encode64(token).delete("\n")
                   "_auth=#{encoded_token}"
                 elsif Base64.decode64(token).ascii_only? &&
                       Base64.decode64(token).include?(":")
                   "_auth=#{token.delete("\n")}"
                 else
                   "_authToken=#{token}"
                 end

          return auth unless registry

          # We need to ensure the registry uri ends with a trailing slash in the npmrc file
          # but we do not want to add one if it already exists
          registry_with_trailing_slash = registry.sub(%r{\/?$}, "/")

          "//#{registry_with_trailing_slash}:#{auth}"
        end

        sig { returns(T.nilable(T::Array[String])) }
        def npmrc_scoped_registries
          return [] unless npmrc_file

          @npmrc_scoped_registries ||= T.let(
            T.must(T.must(npmrc_file).content).lines.select { |line| line.match?(SCOPED_REGISTRY) }
                      .filter_map { |line| line.match(SCOPED_REGISTRY)&.named_captures&.fetch("registry") },
            T.nilable(T::Array[String])
          )
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(registry: String).returns(T.nilable(T::Array[String])) }
        def registry_scopes(registry)
          # Central registries don't just apply to scopes
          return if CENTRAL_REGISTRIES.include?(registry)
          return unless dependency_urls

          other_regs =
            registry_credentials.map { |c| c.fetch("registry") } -
            [registry]
          affected_urls =
            dependency_urls
            &.select do |url|
              next false unless url.include?(registry)

              other_regs.none? { |r| r.include?(registry) && url.include?(r) }
            end

          scopes = T.must(affected_urls).map do |url|
            url.split(/\%40|@/)[1]&.split(%r{\%2[fF]|/})&.first
          end.uniq

          # Registry used for unscoped packages
          return if scopes.include?(nil)

          scopes.map { |scope| "@#{scope}:registry=https://#{registry}" }
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(T::Array[Dependabot::Credential]) }
        def registry_credentials
          credentials.select { |cred| cred.fetch("type") == "npm_registry" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def npmrc_file
          @npmrc_file ||= T.let(
            dependency_files.find { |f| f.name.end_with?(".npmrc") },
            T.nilable(Dependabot::DependencyFile)
          )
        end
      end
    end
  end
end
