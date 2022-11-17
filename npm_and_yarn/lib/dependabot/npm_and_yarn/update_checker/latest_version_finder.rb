# frozen_string_literal: true

require "excon"
require "dependabot/npm_and_yarn/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/npm_and_yarn/update_checker/registry_finder"
require "dependabot/npm_and_yarn/version"
require "dependabot/npm_and_yarn/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"
module Dependabot
  module NpmAndYarn
    class UpdateChecker
      class LatestVersionFinder
        class RegistryError < StandardError
          attr_reader :status

          def initialize(status, msg)
            @status = status
            super(msg)
          end
        end

        def initialize(dependency:, credentials:, dependency_files:,
                       ignored_versions:, security_advisories:,
                       raise_on_ignored: false)
          @dependency          = dependency
          @credentials         = credentials
          @dependency_files    = dependency_files
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
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

        def lowest_security_fix_version
          return unless valid_npm_details?

          secure_versions =
            if specified_dist_tag_requirement?
              [version_from_dist_tags].compact
            else
              possible_versions(filter_ignored: false)
            end

          secure_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(secure_versions,
                                                                                                  security_advisories)
          secure_versions = filter_ignored_versions(secure_versions)
          secure_versions = filter_lower_versions(secure_versions)

          secure_versions.reverse.find { |version| !yanked?(version) }
        rescue Excon::Error::Socket, Excon::Error::Timeout
          raise if dependency_registry == "registry.npmjs.org"
          # Sometimes custom registries are flaky. We don't want to make that
          # our problem, so we quietly return `nil` here.
        end

        def possible_previous_versions_with_details
          @possible_previous_versions_with_details ||= npm_details.fetch("versions", {}).
                                                       transform_keys { |k| version_class.new(k) }.
                                                       reject { |v, _| v.prerelease? && !related_to_current_pre?(v) }.
                                                       sort_by(&:first).reverse
        end

        def possible_versions_with_details(filter_ignored: true)
          versions = possible_previous_versions_with_details.
                     reject { |_, details| details["deprecated"] }

          return filter_ignored_versions(versions) if filter_ignored

          versions
        end

        def possible_versions(filter_ignored: true)
          possible_versions_with_details(filter_ignored: filter_ignored).
            map(&:first)
        end

        private

        attr_reader :dependency, :credentials, :dependency_files,
                    :ignored_versions, :security_advisories

        def valid_npm_details?
          !npm_details&.fetch("dist-tags", nil).nil?
        end

        def filter_ignored_versions(versions_array)
          filtered = versions_array.reject do |v, _|
            ignore_requirements.any? { |r| r.satisfied_by?(v) }
          end

          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise AllVersionsIgnored
          end

          filtered
        end

        def filter_out_of_range_versions(versions_array)
          reqs = dependency.requirements.filter_map do |r|
            NpmAndYarn::Requirement.requirements_array(r.fetch(:requirement))
          end

          versions_array.
            select { |v| reqs.all? { |r| r.any? { |o| o.satisfied_by?(v) } } }
        end

        def filter_lower_versions(versions_array)
          return versions_array unless dependency.numeric_version

          versions_array.
            select { |version, _| version > dependency.numeric_version }
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
          current_version = dependency.numeric_version
          if current_version&.prerelease? &&
             current_version&.release == version.release
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
          return false if ignore_requirements.any? { |r| r.satisfied_by?(ver) }
          return false if yanked?(ver)

          true
        end

        def current_version_greater_than?(version)
          return false unless dependency.numeric_version

          dependency.numeric_version > version
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
              status = Dependabot::RegistryClient.get(
                url: dependency_url + "/#{version}",
                headers: registry_auth_headers
              ).status

              if status == 404 && dependency_registry != "registry.npmjs.org"
                # Some registries don't handle escaped package names properly
                status = Dependabot::RegistryClient.get(
                  url: dependency_url.gsub("%2F", "/") + "/#{version}",
                  headers: registry_auth_headers
                ).status
              end

              version_not_found = status == 404
              version_not_found && version_endpoint_working?
            rescue Excon::Error::Timeout, Excon::Error::Socket
              # Give the benefit of the doubt if the registry is playing up
              false
            end
        end

        def version_endpoint_working?
          return true if dependency_registry == "registry.npmjs.org"

          return @version_endpoint_working if defined?(@version_endpoint_working)

          @version_endpoint_working =
            begin
              Dependabot::RegistryClient.get(
                url: dependency_url + "/latest",
                headers: registry_auth_headers
              ).status < 400
            rescue Excon::Error::Timeout, Excon::Error::Socket
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
            rescue JSON::ParserError,
                   Excon::Error::Timeout,
                   Excon::Error::Socket,
                   RegistryError => e
              if git_dependency?
                nil
              else
                raise_npm_details_error(e)
              end
            end
        end

        def fetch_npm_response
          response = Dependabot::RegistryClient.get(
            url: dependency_url,
            headers: registry_auth_headers
          )
          return response unless response.status == 500
          return response unless registry_auth_headers["Authorization"]

          auth = registry_auth_headers["Authorization"]
          return response unless auth.start_with?("Basic")

          decoded_token = Base64.decode64(auth.gsub("Basic ", ""))
          return unless decoded_token.include?(":")

          username, password = decoded_token.split(":")
          Dependabot::RegistryClient.get(
            url: dependency_url,
            options: {
              user: username,
              password: password
            }
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
          raise RegistryError.new(status, msg)
        end

        def raise_npm_details_error(error)
          raise if dependency_registry == "registry.npmjs.org"
          raise unless error.is_a?(Excon::Error::Timeout)

          raise PrivateSourceTimedOut, dependency_registry
        end

        def private_dependency_not_reachable?(npm_response)
          return true if npm_response.body.start_with?(/user ".*?" is not a /)
          return false unless [401, 402, 403, 404].include?(npm_response.status)

          # Check whether this dependency is (likely to be) private
          if dependency_registry == "registry.npmjs.org"
            return false unless dependency.name.start_with?("@")

            web_response = Dependabot::RegistryClient.get(url: "https://www.npmjs.com/package/#{dependency.name}")
            # NOTE: returns 429 when the login page is rate limited
            return web_response.body.include?("Forgot password?") ||
                   web_response.status == 429
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
            yarnrc_file: yarnrc_file,
            yarnrc_yml_file: yarnrc_yml_file
          )
        end

        def ignore_requirements
          ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
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

        def yarnrc_yml_file
          dependency_files.find { |f| f.name.end_with?(".yarnrc.yml") }
        end

        # TODO: Remove need for me
        def git_dependency?
          # ignored_version/raise_on_ignored are irrelevant.
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          ).git_dependency?
        end
      end
    end
  end
end
