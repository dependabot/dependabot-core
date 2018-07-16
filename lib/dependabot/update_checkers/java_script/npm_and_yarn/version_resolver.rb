# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/java_script/npm_and_yarn"
require "dependabot/update_checkers/java_script/npm_and_yarn/registry_finder"
require "dependabot/utils/java_script/version"
require "dependabot/utils/java_script/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class NpmAndYarn
        class VersionResolver
          class RegistryError < StandardError; end

          def initialize(dependency:, credentials:, dependency_files:,
                         ignored_versions:)
            @dependency       = dependency
            @credentials      = credentials
            @dependency_files = dependency_files
            @ignored_versions = ignored_versions
          end

          def latest_version_details_from_registry
            return nil unless npm_details&.fetch("dist-tags", nil)

            dist_tag_version = version_from_dist_tags(npm_details)
            return { version: dist_tag_version } if dist_tag_version
            return nil if specified_dist_tag_requirement?

            { version: version_from_versions_array }
          rescue Excon::Error::Socket, Excon::Error::Timeout
            raise if dependency_registry == "registry.npmjs.org"
            # Custom registries can be flaky. We don't want to make that
            # our problem, so we quietly return `nil` here.
          end

          def latest_resolvable_version_with_no_unlock
            return unless npm_details

            reqs = dependency.requirements.map do |r|
              Utils::JavaScript::Requirement.
                requirements_array(r.fetch(:requirement))
            end.compact

            npm_versions_array.
              find do |version|
                reqs.all? { |r| r.any? { |opt| opt.satisfied_by?(version) } } &&
                  !yanked?(version)
              end
          rescue Excon::Error::Socket, Excon::Error::Timeout
            raise if dependency_registry == "registry.npmjs.org"
            # Sometimes custom registries are flaky. We don't want to make that
            # our problem, so we quietly return `nil` here.
          end

          private

          attr_reader :dependency, :credentials, :dependency_files,
                      :ignored_versions

          def version_from_dist_tags(npm_details)
            dist_tags = npm_details["dist-tags"].keys

            # Check if a dist tag was specified as a requirement. If it was, and
            # it exists, use it.
            dist_tag_req =
              dependency.requirements.
              find { |req| dist_tags.include?(req[:requirement]) }&.
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
              Utils::JavaScript::Requirement.
                requirements_array(req.fetch(:requirement)).
                any? do |r|
                  r.requirements.any? { |a| a.last.release == version.release }
                end
            end
          end

          def specified_dist_tag_requirement?
            dependency.requirements.any? do |req|
              next false if req[:requirement].nil?
              req[:requirement].match?(/^[A-Za-z]/)
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

          def version_from_versions_array
            npm_versions_array.find { |version| !yanked?(version) }
          end

          def npm_versions_array
            npm_details.fetch("versions", {}).
              reject { |_, details| details["deprecated"] }.
              keys.map { |v| version_class.new(v) }.
              reject { |v| v.prerelease? && !related_to_current_pre?(v) }.
              reject { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }.
              sort.reverse
          end

          def yanked?(version)
            Excon.get(
              dependency_url + "/#{version}",
              SharedHelpers.excon_defaults.merge(
                headers: registry_auth_headers,
                idempotent: true
              )
            ).status == 404
          rescue Excon::Error::Timeout
            # Give the benefit of the doubt if the registry is playing up
            false
          end

          def npm_details
            return @npm_details if @npm_details_lookup_attempted
            @npm_details_lookup_attempted = true
            @npm_details ||=
              begin
                npm_response = Excon.get(
                  dependency_url,
                  SharedHelpers.excon_defaults.merge(
                    headers: registry_auth_headers,
                    idempotent: true
                  )
                )

                check_npm_response(npm_response)

                JSON.parse(npm_response.body)
              rescue JSON::ParserError, Excon::Error::Timeout,
                     RegistryError => error
                retry_count ||= 0
                retry_count += 1
                if retry_count > 2
                  raise if dependency_registry == "registry.npmjs.org"
                  raise unless error.is_a?(Excon::Error::Timeout)
                  raise PrivateSourceTimedOut, dependency_registry
                end
                sleep(rand(3.0..10.0)) && retry
              end
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

          def private_dependency_not_reachable?(npm_response)
            # Check whether this dependency is (likely to be) private
            if dependency_registry == "registry.npmjs.org" &&
               !dependency.name.start_with?("@")
              return false
            end

            return true if [401, 402, 403, 404].include?(npm_response.status)

            # Temporary workaround for npm bug on 2018-07-13. Remove me!
            npm_response.status == 500 &&
              npm_response.body.include?("Cannot read property 'then'")
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
            @registry_finder ||=
              NpmAndYarn::RegistryFinder.new(
                dependency: dependency,
                credentials: credentials,
                npmrc_file: dependency_files.find { |f| f.name == ".npmrc" }
              )
          end

          def ignore_reqs
            ignored_versions.
              map { |req| Utils::JavaScript::Requirement.new(req.split(",")) }
          end

          def version_class
            Utils::JavaScript::Version
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
end
