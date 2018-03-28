# frozen_string_literal: true

require "dependabot/file_updaters/java_script/npm_and_yarn"

module Dependabot
  module FileUpdaters
    module JavaScript
      class NpmAndYarn
        # Build a .npmrc file from the lockfile content, credentials, and any
        # committed .npmrc
        class NpmrcBuilder
          CENTRAL_REGISTRIES = %w(
            registry.npmjs.org
            registry.yarnpkg.com
          ).freeze

          def initialize(dependency_files:, credentials:)
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def npmrc_content
            initial_content =
              if npmrc_file.nil? then build_npmrc_from_lockfile
              else complete_npmrc_from_credentials
              end

            ([initial_content] + credential_lines_for_npmrc).compact.join("\n")
          end

          private

          attr_reader :dependency_files, :credentials

          def build_npmrc_from_lockfile
            return build_npmrc_from_package_lock if package_lock
            return build_npmrc_from_yarn_lock if yarn_lock
          end

          def build_npmrc_from_package_lock
            dependency_urls =
              parsed_package_lock.fetch("dependencies", {}).
              map { |_, details| details["resolved"] }.compact.
              reject { |url| url.start_with?("git") }

            global_registry =
              registry_credentials.find do |cred|
                next false if CENTRAL_REGISTRIES.include?(cred["registry"])
                dependency_urls.all? { |url| url.include?(cred["registry"]) }
              end

            return unless global_registry

            "registry = https://#{global_registry['registry']}\n"\
            "_auth = #{global_registry.fetch('token')}\n"\
            "always-auth = true"
          end

          def build_npmrc_from_yarn_lock
            dependency_urls =
              yarn_lock.content.scan(/ resolved "(.*?)"/).flatten

            global_registry =
              registry_credentials.find do |cred|
                next false if CENTRAL_REGISTRIES.include?(cred["registry"])
                dependency_urls.all? { |url| url.include?(cred["registry"]) }
              end

            return unless global_registry

            "registry = https://#{global_registry['registry']}\n"\
            "_auth = #{global_registry.fetch('token')}\n"\
            "always-auth = true"
          end

          def complete_npmrc_from_credentials
            initial_content = npmrc_file.content.gsub(/^.*:_authToken=\$.*/, "")

            return initial_content unless (cred = registry_credentials.first)

            initial_content.gsub(/^_auth\s*=\s*\${.*}/) do |ln|
              ln.sub(/\${.*}/, cred.fetch("token"))
            end
          end

          def credential_lines_for_npmrc
            credential_lines = registry_credentials.map do |cred|
              if cred.fetch("token").include?(":")
                encoded_token = Base64.encode64(cred.fetch("token")).chomp
                "//#{cred['registry']}/:_auth=#{encoded_token}"
              else
                "//#{cred['registry']}/:_authToken=#{cred.fetch('token')}"
              end
            end

            unless credential_lines.any? { |str| str.include?("auth=") }
              return credential_lines
            end

            ["always-auth = true"] + credential_lines
          end

          def registry_credentials
            credentials.select { |cred| cred.key?("registry") }
          end

          def parsed_package_lock
            @parsed_package_lock ||= JSON.parse(package_lock.content)
          end

          def npmrc_file
            @npmrc_file ||= dependency_files.find { |f| f.name == ".npmrc" }
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
end
