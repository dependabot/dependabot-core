# frozen_string_literal: true

require "dependabot/npm_and_yarn/file_updater"

module Dependabot
  module NpmAndYarn
    class FileUpdater
      # Build a .npmrc file from the lockfile content, credentials, and any
      # committed .npmrc
      class NpmrcBuilder
        CENTRAL_REGISTRIES = %w(
          registry.npmjs.org
          registry.yarnpkg.com
        ).freeze

        SCOPED_REGISTRY = /^\s*@(?<scope>\S+):registry\s*=\s*(?<registry>\S+)/.freeze

        def initialize(dependency_files:, credentials:)
          @dependency_files = dependency_files
          @credentials = credentials
        end

        # PROXY WORK
        def npmrc_content
          initial_content =
            if npmrc_file then complete_npmrc_from_credentials
            elsif yarnrc_file then build_npmrc_from_yarnrc
            else
              build_npmrc_content_from_lockfile
            end

          return initial_content || "" unless registry_credentials.any?

          ([initial_content] + credential_lines_for_npmrc).compact.join("\n")
        end

        private

        attr_reader :dependency_files, :credentials

        def build_npmrc_content_from_lockfile
          return unless yarn_lock || package_lock
          return unless global_registry

          "registry = https://#{global_registry['registry']}\n" \
            "#{global_registry_auth_line}" \
            "always-auth = true"
        end

        def global_registry # rubocop:disable Metrics/PerceivedComplexity
          return @global_registry if defined?(@global_registry)

          @global_registry =
            registry_credentials.find do |cred|
              next false if CENTRAL_REGISTRIES.include?(cred["registry"])

              # If all the URLs include this registry, it's global
              next true if dependency_urls.all? { |url| url.include?(cred["registry"]) }

              # Check if this registry has already been defined in .npmrc as a scoped registry
              next false if npmrc_scoped_registries.any? { |sr| sr.include?(cred["registry"]) }

              # If any unscoped URLs include this registry, assume it's global
              dependency_urls.
                reject { |u| u.include?("@") || u.include?("%40") }.
                any? { |url| url.include?(cred["registry"]) }
            end
        end

        def global_registry_auth_line
          token = global_registry.fetch("token", nil)
          return "" unless token

          if token.include?(":")
            encoded_token = Base64.encode64(token).delete("\n")
            "_auth = #{encoded_token}\n"
          elsif Base64.decode64(token).ascii_only? &&
                Base64.decode64(token).include?(":")
            "_auth = #{token.delete("\n")}\n"
          else
            "_authToken = #{token}\n"
          end
        end

        def dependency_urls
          return @dependency_urls if defined?(@dependency_urls)

          @dependency_urls = []
          if package_lock
            @dependency_urls +=
              parsed_package_lock.fetch("dependencies", {}).
              filter_map { |_, details| details["resolved"] }.
              select { |url| url.is_a?(String) }.
              reject { |url| url.start_with?("git") }
          end
          if yarn_lock
            @dependency_urls +=
              yarn_lock.content.scan(/ resolved "(.*?)"/).flatten
          end

          # The registry URL for Bintray goes into the lockfile in a
          # modified format, so we modify it back before checking against
          # our credentials
          @dependency_urls =
            @dependency_urls.map do |url|
              url.gsub("dl.bintray.com//", "api.bintray.com/npm/")
            end
        end

        def complete_npmrc_from_credentials
          initial_content = npmrc_file.content.
                            gsub(/^.*\$\{.*\}.*/, "").strip + "\n"
          return initial_content unless yarn_lock || package_lock
          return initial_content unless global_registry

          initial_content +
            "registry = https://#{global_registry['registry']}\n" \
            "#{global_registry_auth_line}" \
            "always-auth = true\n"
        end

        def build_npmrc_from_yarnrc
          yarnrc_global_registry =
            yarnrc_file.content.
            lines.find { |line| line.match?(/^\s*registry\s/) }&.
            match(/^\s*registry\s+"(?<registry>[^"]+)"/)&.
            named_captures&.fetch("registry")

          return "registry = #{yarnrc_global_registry}\n" if yarnrc_global_registry

          build_npmrc_content_from_lockfile
        end

        def credential_lines_for_npmrc
          lines = []
          registry_credentials.each do |cred|
            registry = cred.fetch("registry")

            lines += registry_scopes(registry) if registry_scopes(registry)

            token = cred.fetch("token", nil)
            next unless token

            # We need to ensure the registry uri ends with a trailing slash in the npmrc file
            # but we do not want to add one if it already exists
            registry_with_trailing_slash = registry.sub(%r{\/?$}, "/")
            if token.include?(":")
              encoded_token = Base64.encode64(token).delete("\n")
              lines << "//#{registry_with_trailing_slash}:_auth=#{encoded_token}"
            elsif Base64.decode64(token).ascii_only? &&
                  Base64.decode64(token).include?(":")
              lines << %(//#{registry_with_trailing_slash}:_auth=#{token.delete("\n")})
            else
              lines << "//#{registry_with_trailing_slash}:_authToken=#{token}"
            end
          end

          return lines unless lines.any? { |str| str.include?("auth=") }

          # Work around a suspected yarn bug
          ["always-auth = true"] + lines
        end

        def npmrc_scoped_registries
          return [] unless npmrc_file

          @npmrc_scoped_registries ||=
            npmrc_file.content.lines.select { |line| line.match?(SCOPED_REGISTRY) }.
            filter_map { |line| line.match(SCOPED_REGISTRY)&.named_captures&.fetch("registry") }
            
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def registry_scopes(registry)
          # Central registries don't just apply to scopes
          return if CENTRAL_REGISTRIES.include?(registry)
          return unless dependency_urls

          other_regs =
            registry_credentials.map { |c| c.fetch("registry") } -
            [registry]
          affected_urls =
            dependency_urls.
            select do |url|
              next false unless url.include?(registry)

              other_regs.none? { |r| r.include?(registry) && url.include?(r) }
            end

          scopes = affected_urls.map do |url|
            url.split(/\%40|@/)[1]&.split(%r{\%2[fF]|/})&.first
          end

          # Registry used for unscoped packages
          return if scopes.include?(nil)

          scopes.map { |scope| "@#{scope}:registry=https://#{registry}" }
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def registry_credentials
          credentials.select { |cred| cred.fetch("type") == "npm_registry" }
        end

        def parsed_package_lock
          @parsed_package_lock ||= JSON.parse(package_lock.content)
        end

        def npmrc_file
          @npmrc_file ||= dependency_files.
                          find { |f| f.name.end_with?(".npmrc") }
        end

        def yarnrc_file
          @yarnrc_file ||= dependency_files.
                           find { |f| f.name.end_with?(".yarnrc") }
        end

        def yarn_lock
          @yarn_lock ||= dependency_files.find { |f| f.name == "yarn.lock" }
        end

        def package_lock
          @package_lock ||=
            dependency_files.find { |f| f.name == "package-lock.json" }
        end
      end
    end
  end
end
