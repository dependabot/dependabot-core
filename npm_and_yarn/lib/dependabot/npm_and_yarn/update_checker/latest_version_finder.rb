# frozen_string_literal: true

require "excon"
require "dependabot/npm_and_yarn/update_checker"
require "dependabot/npm_and_yarn/update_checker/registry_finder"
require "dependabot/npm_and_yarn/version"
require "dependabot/npm_and_yarn/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"

# rubocop:disable ClassLength
module Dependabot
  module NpmAndYarn
    class UpdateChecker
      class LatestVersionFinder
        class RegistryError < StandardError; end

        def initialize(dependency:, credentials:, dependency_files:,
                       ignored_versions:, security_advisories:)
          @dependency          = dependency
          @credentials         = credentials
          @dependency_files    = dependency_files
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
        end

        def latest_version_from_registry
          return unless valid_npm_details?
          return version_from_dist_tags if version_from_dist_tags
          return if specified_dist_tag_requirement?

          possible_versions.find { |v| !yanked?(v) }
        rescue Excon::Error::Socket, Excon::Error::Timeout, RegistryError
          raise if dependency_registry == "registry.npmjs.org"
          # Custom registries can be flaky. We don't want to make that
          # our problem, so we quietly return `nil` here.
        end

        def latest_version_with_no_unlock
          return unless valid_npm_details?
          return version_from_dist_tags if specified_dist_tag_requirement?

          in_range_versions = filter_out_of_range_versions(possible_versions)
          in_range_versions.find { |version| !yanked?(version) }
        rescue Excon::Error::Socket, Excon::Error::Timeout
          raise if dependency_registry == "registry.npmjs.org"
          # Sometimes custom registries are flaky. We don't want to make that
          # our problem, so we quietly return `nil` here.
        end

        def possible_versions_with_details
          npm_details.fetch("versions", {}).
            reject { |_, details| details["deprecated"] }.
            transform_keys { |k| version_class.new(k) }.
            reject { |k, _| k.prerelease? && !related_to_current_pre?(k) }.
            reject { |k, _| ignore_reqs.any? { |r| r.satisfied_by?(k) } }.
            sort_by(&:first).reverse
        end

        def possible_versions
          possible_versions_with_details.map(&:first)
        end

        private

        attr_reader :dependency, :credentials, :dependency_files,
                    :ignored_versions, :security_advisories

        def valid_npm_details?
          !npm_details&.fetch("dist-tags", nil).nil?
        end

        def filter_out_of_range_versions(possible_versions)
          reqs = dependency.requirements.map do |r|
            NpmAndYarn::Requirement.requirements_array(r.fetch(:requirement))
          end.compact

          possible_versions.
            select { |v| reqs.all? { |r| r.any? { |o| o.satisfied_by?(v) } } }
        end

        def version_from_dist_tags
          dist_tags = npm_details["dist-tags"].keys

          # Check if a dist tag was specified as a requirement. If it was, and
          # it exists, use it.
          dist_tag_req = dependency.requirements.
                         find { |r| dist_tags.include?(r[:requirement]) }&.
                         fetch(:requirement)

          if dist_tag_req
            tag_vers =
              version_class.new(npm_details["dist-tags"][dist_tag_req])
            return tag_vers unless yanked?(tag_vers)
          end

          # Use the latest dist tag unless there's a reason not to
          return nil unless npm_details["dist-tags"]["latest"]

          latest = version_class.new(npm_details["dist-tags"]["latest"])

          wants_latest_dist_tag?(latest) ? latest : nil
        end

        def related_to_current_pre?(version)
          current_version = dependency.version
          if current_version &&
             version_class.correct?(current_version) &&
             version_class.new(current_version).prerelease? &&
             version_class.new(current_version).release == version.release
            return true
          end

          dependency.requirements.any? do |req|
            next unless req[:requirement]&.match?(/\d-[A-Za-z]/)

            NpmAndYarn::Requirement.
              requirements_array(req.fetch(:requirement)).
              any? do |r|
                r.requirements.any? { |a| a.last.release == version.release }
              end
          rescue Gem::Requirement::BadRequirementError
            false
          end
        end

        def specified_dist_tag_requirement?
          dependency.requirements.any? do |req|
            next false if req[:requirement].nil?
            next false unless req[:requirement].match?(/^[A-Za-z]/)

            !req[:requirement].match?(/^v\d/i)
          end
        end

        def wants_latest_dist_tag?(latest_version)
          ver = latest_version
          return false if related_to_current_pre?(ver) ^ ver.prerelease?
          return false if current_version_greater_than?(ver)
          return false if current_requirement_greater_than?(ver)
          return false if ignore_reqs.any? { |r| r.satisfied_by?(ver) }
          return false if yanked?(ver)

          true
        end

        def current_version_greater_than?(version)
          return false unless dependency.version
          return false unless version_class.correct?(dependency.version)

          version_class.new(dependency.version) > version
        end

        def current_requirement_greater_than?(version)
          dependency.requirements.any? do |req|
            next false unless req[:requirement]

            req_version = req[:requirement].sub(/^\^|~|>=?/, "")
            next false unless version_class.correct?(req_version)

            version_class.new(req_version) > version
          end
        end

        def yanked?(version)
          @yanked ||= {}
          return @yanked[version] if @yanked.key?(version)

          @yanked[version] =
            begin
              status = Excon.get(
                dependency_url + "/#{version}",
                headers: registry_auth_headers,
                idempotent: true,
                **SharedHelpers.excon_defaults
              ).status

              if status == 404 && dependency_registry != "registry.npmjs.org"
                # Some registries don't handle escaped package names properly
                status = Excon.get(
                  dependency_url.gsub("%2F", "/") + "/#{version}",
                  headers: registry_auth_headers,
                  idempotent: true,
                  **SharedHelpers.excon_defaults
                ).status
              end

              version_not_found = status == 404
              version_not_found && version_endpoint_working?
            rescue Excon::Error::Timeout
              # Give the benefit of the doubt if the registry is playing up
              false
            end
        end

        def version_endpoint_working?
          return true if dependency_registry == "registry.npmjs.org"

          if defined?(@version_endpoint_working)
            return @version_endpoint_working
          end

          @version_endpoint_working =
            begin
              Excon.get(
                dependency_url + "/latest",
                headers: registry_auth_headers,
                idempotent: true,
                **SharedHelpers.excon_defaults
              ).status < 400
            rescue Excon::Error::Timeout
              # Give the benefit of the doubt if the registry is playing up
              true
            end
        end

        def npm_details
          return @npm_details if @npm_details_lookup_attempted

          @npm_details_lookup_attempted = true
          @npm_details ||=
            begin
              npm_response = fetch_npm_response

              check_npm_response(npm_response)
              JSON.parse(npm_response.body)
            rescue JSON::ParserError, Excon::Error::Timeout, RegistryError => e
              return if git_dependency?

              retry_count ||= 0
              retry_count += 1
              raise_npm_details_error(e) if retry_count > 2
              sleep(rand(3.0..10.0)) && retry
            end
        end

        def fetch_npm_response
          response = Excon.get(
            dependency_url,
            headers: registry_auth_headers,
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          return response unless response.status == 500
          return response unless registry_auth_headers["Authorization"]

          auth = registry_auth_headers["Authorization"]
          return response unless auth.start_with?("Basic")

          decoded_token = Base64.decode64(auth.gsub("Basic ", ""))
          return unless decoded_token.include?(":")

          username, password = decoded_token.split(":")
          Excon.get(
            dependency_url,
            user: username,
            password: password,
            idempotent: true,
            **SharedHelpers.excon_defaults
          )
        end

        def check_npm_response(npm_response)
          return if git_dependency?

          if private_dependency_not_reachable?(npm_response)
            raise PrivateSourceAuthenticationFailure, dependency_registry
          end

          status = npm_response.status
          return if status.to_s.start_with?("2")

          # Ignore 404s from the registry for updates where a lockfile doesn't
          # need to be generated. The 404 won't cause problems later.
          return if status == 404 && dependency.version.nil?

          msg = "Got #{status} response with body #{npm_response.body}"
          raise RegistryError, msg
        end

        def raise_npm_details_error(error)
          raise if dependency_registry == "registry.npmjs.org"
          raise unless error.is_a?(Excon::Error::Timeout)

          raise PrivateSourceTimedOut, dependency_registry
        end

        def private_dependency_not_reachable?(npm_response)
          return false unless [401, 402, 403, 404].include?(npm_response.status)

          # Check whether this dependency is (likely to be) private
          if dependency_registry == "registry.npmjs.org"
            return false unless dependency.name.start_with?("@")

            web_response = Excon.get(
              "https://www.npmjs.com/package/#{dependency.name}",
              idempotent: true,
              **SharedHelpers.excon_defaults
            )
            return web_response.body.include?("Forgot password?")
          end

          true
        end

        def dependency_url
          registry_finder.dependency_url
        end

        def dependency_registry
          registry_finder.registry
        end

        def registry_auth_headers
          registry_finder.auth_headers
        end

        def registry_finder
          @registry_finder ||= RegistryFinder.new(
            dependency: dependency,
            credentials: credentials,
            npmrc_file: npmrc_file,
            yarnrc_file: yarnrc_file
          )
        end

        def ignore_reqs
          ignored_versions.map { |req| requirement_class.new(req.split(",")) }
        end

        def version_class
          NpmAndYarn::Version
        end

        def requirement_class
          NpmAndYarn::Requirement
        end

        def npmrc_file
          dependency_files.find { |f| f.name.end_with?(".npmrc") }
        end

        def yarnrc_file
          dependency_files.find { |f| f.name.end_with?(".yarnrc") }
        end

        # TODO: Remove need for me
        def git_dependency?
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          ).git_dependency?
        end
      end
    end
  end
end
# rubocop:enable ClassLength
