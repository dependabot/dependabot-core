# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class Base < Dependabot::UpdateCheckers::Base
        require_relative "base/requirements_updater"

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          # Javascript doesn't have the concept of version conflicts, so the
          # latest version is always resolvable.
          latest_version
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            latest_resolvable_version: latest_resolvable_version&.to_s,
            existing_version: dependency.version&.to_s
          ).updated_requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for JS (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def fetch_latest_version
          latest_dist_tag = npm_details["dist-tags"]["latest"]
          latest_dist_tag = Gem::Version.new(latest_dist_tag)
          return latest_dist_tag if use_latest_dist_tag?(latest_dist_tag)

          latest_release =
            npm_details["versions"].
            keys.map { |v| Gem::Version.new(v) }.
            reject { |v| v.prerelease? && !wants_prerelease? }.sort.reverse.
            find { |version| !yanked?(version) }

          Gem::Version.new(latest_release)
        rescue Excon::Error::Socket, Excon::Error::Timeout
          raise if dependency_registry == "registry.npmjs.org"
          # Sometimes custom registries are flaky. We don't want to make that
          # our problem, so we quietly return `nil` here.
        end

        def use_latest_dist_tag?(version)
          !wants_prerelease? && !version.prerelease? && !yanked?(version)
        end

        def yanked?(version)
          Excon.get(
            dependency_url + "/#{version}",
            headers: registry_auth_headers,
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          ).status == 404
        end

        def npm_details
          @npm_details =
            begin
              npm_response = Excon.get(
                dependency_url,
                headers: registry_auth_headers,
                idempotent: true,
                middlewares: SharedHelpers.excon_middleware
              )

              if private_dependency_not_reachable?(npm_response)
                raise PrivateSourceNotReachable, dependency_registry
              end

              JSON.parse(npm_response.body)
            rescue JSON::ParserError
              @retry_count ||= 0
              @retry_count += 1
              retry unless @retry_count > 1
              raise
            end
        end

        def private_dependency_not_reachable?(npm_response)
          # Check whether this dependency is (likely to be) private
          if dependency_registry == "registry.npmjs.org" &&
             !dependency.name.start_with?("@")
            return false
          end

          [401, 403, 404].include?(npm_response.status)
        end

        def wants_prerelease?
          current_version = dependency.version
          if current_version && Gem::Version.new(current_version).prerelease?
            return true
          end

          # TODO: Handle pre-release requirements, too
          false
        end

        def dependency_url
          source =
            dependency.requirements.map { |r| r.fetch(:source) }.compact.first

          registry_url =
            if source.nil? then "https://registry.npmjs.org"
            else source.fetch(:url)
            end

          # npm registries expect slashes to be escaped
          escaped_dependency_name = dependency.name.gsub("/", "%2F")
          "#{registry_url}/#{escaped_dependency_name}"
        end

        def dependency_registry
          source =
            dependency.requirements.map { |r| r.fetch(:source) }.compact.first

          if source.nil? then "registry.npmjs.org"
          else source.fetch(:url).gsub("https://", "").gsub("http://", "")
          end
        end

        def registry_auth_headers
          return {} unless auth_token
          { "Authorization" => "Bearer #{auth_token}" }
        end

        def auth_token
          env_token =
            credentials.
            find { |cred| cred["registry"] == dependency_registry }&.
            fetch("token")

          return env_token if env_token
          return unless npmrc

          auth_token_regex = %r{//(?<registry>.*)/:_authToken=(?<token>.*)$}
          matches = []
          npmrc.content.scan(auth_token_regex) { matches << Regexp.last_match }

          npmrc_token =
            matches.find { |match| match[:registry] == dependency_registry }&.
            [](:token)

          return if npmrc_token.nil? || npmrc_token.start_with?("${")
          npmrc_token
        end

        def npmrc
          @npmrc ||= dependency_files.find { |f| f.name == ".npmrc" }
        end
      end
    end
  end
end
