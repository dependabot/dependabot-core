# typed: strict
# frozen_string_literal: true

require "excon"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/package/package_latest_version_finder"
require "dependabot/bun/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/bun/package/registry_finder"
require "dependabot/bun/package/package_details_fetcher"
require "dependabot/bun/version"
require "dependabot/bun/requirement"
require "sorbet-runtime"

module Dependabot
  module Bun
    class UpdateChecker
      class PackageLatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            raise_on_ignored: T::Boolean,
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          raise_on_ignored: false,
          cooldown_options: nil
        )
          @package_fetcher = T.let(nil, T.nilable(Package::PackageDetailsFetcher))
          super
        end

        sig { returns(Package::PackageDetailsFetcher) }
        def package_fetcher
          return @package_fetcher if @package_fetcher

          @package_fetcher = Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          )
          @package_fetcher
        end

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          return @package_details if @package_details

          @package_details = package_fetcher.fetch
          @package_details
        end

        sig do
          returns(T.nilable(Dependabot::Version))
        end
        def latest_version_from_registry
          fetch_latest_version(language_version: nil)
        end

        sig do
          override.params(language_version: T.nilable(T.any(String, Dependabot::Version)))
                  .returns(T.nilable(Dependabot::Version))
        end
        def latest_version_with_no_unlock(language_version: nil)
          with_custom_registry_rescue do
            return unless valid_npm_details?
            return version_from_dist_tags&.version if specified_dist_tag_requirement?

            super
          end
        end

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def lowest_security_fix_version(language_version: nil)
          fetch_lowest_security_fix_version(language_version: language_version)
        end

        # This method is for latest_version_from_registry
        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version(language_version: nil)
          with_custom_registry_rescue do
            return unless valid_npm_details?

            tag_release = version_from_dist_tags
            return tag_release.version if tag_release

            return if specified_dist_tag_requirement?

            super
          end
        end

        sig do
          override
            .params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version_with_no_unlock(language_version: nil)
          with_custom_registry_rescue do
            return unless valid_npm_details?
            return version_from_dist_tags&.version if specified_dist_tag_requirement?

            super
          end
        end

        sig do
          override
            .params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_latest_versions_filter(releases)
          original_count = releases.count
          filtered_versions = lazy_filter_yanked_versions_by_min_max(releases, check_max: true)

          # Log the filter if any versions were removed
          if original_count > filtered_versions.count
            Dependabot.logger.info(
              "Filtered out #{original_count - filtered_versions.count} " \
              "yanked (not found) versions after fetching latest versions"
            )
          end

          filtered_versions
        end

        sig do
          params(
            releases: T::Array[Dependabot::Package::PackageRelease],
            check_max: T::Boolean
          ).returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def lazy_filter_yanked_versions_by_min_max(releases, check_max: true)
          # Sort the versions based on the check_max flag (max -> descending, min -> ascending)
          sorted_releases = if check_max
                              releases.sort_by(&:version).reverse
                            else
                              releases.sort_by(&:version)
                            end

          filtered_versions = []

          not_yanked = T.let(false, T::Boolean)

          # Iterate through the sorted versions lazily, filtering out yanked versions
          sorted_releases.each do |release|
            next if !not_yanked && yanked_version?(release.version)

            not_yanked = true

            # Once we find a valid (non-yanked) version, add it to the filtered list
            filtered_versions << release
            break
          end

          filtered_versions
        end

        sig do
          override
            .params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_lowest_security_fix_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          with_custom_registry_rescue do
            return unless valid_npm_details?

            secure_versions =
              if specified_dist_tag_requirement?
                [version_from_dist_tags].compact
              else
                possible_releases(filter_ignored: false)
              end

            secure_versions =
              Dependabot::UpdateCheckers::VersionFilters
              .filter_vulnerable_versions(
                T.unsafe(secure_versions),
                security_advisories
              )
            secure_versions = filter_ignored_versions(secure_versions)
            secure_versions = filter_lower_versions(secure_versions)

            # Apply lazy filtering for yanked versions (min or max logic)
            secure_versions = lazy_filter_yanked_versions_by_min_max(secure_versions, check_max: false)

            # Return the lowest non-yanked version
            secure_versions.max_by(&:version)&.version
          end
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_prerelease_versions(releases)
          filtered = releases.reject do |release|
            release.version.prerelease? && !related_to_current_pre?(release.version)
          end

          if releases.count > filtered.count
            Dependabot.logger.info(
              "Filtered out #{releases.count - filtered.count} unrelated pre-release versions"
            )
          end

          filtered
        end

        sig do
          params(filter_ignored: T::Boolean)
            .returns(T::Array[T::Array[T.untyped]])
        end
        def possible_versions_with_details(filter_ignored: true)
          possible_releases(filter_ignored: filter_ignored).map { |r| [r.version, r.details] }
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_releases(releases)
          filtered =
            releases
            .reject do |release|
              ignore_requirements.any? { |r| r.satisfied_by?(release.version) }
            end
          if @raise_on_ignored &&
             filter_lower_releases(filtered).empty? &&
             filter_lower_releases(releases).any?
            raise Dependabot::AllVersionsIgnored
          end

          if releases.count > filtered.count
            Dependabot.logger.info("Filtered out #{releases.count - filtered.count} ignored versions")
          end
          filtered
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_lower_releases(releases)
          return releases unless dependency.numeric_version

          releases.select { |release| release.version > dependency.numeric_version }
        end

        sig do
          params(filter_ignored: T::Boolean)
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def possible_releases(filter_ignored: true)
          releases = possible_previous_releases.reject(&:yanked?)

          return filter_releases(releases) if filter_ignored

          releases
        end

        sig do
          params(filter_ignored: T::Boolean)
            .returns(T::Array[Gem::Version])
        end
        def possible_versions(filter_ignored: true)
          possible_releases(filter_ignored: filter_ignored).map(&:version)
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def possible_previous_releases
          (package_details&.releases || [])
            .reject do |r|
            r.version.prerelease? && !related_to_current_pre?(T.unsafe(r.version))
          end
            .sort_by(&:version).reverse
        end

        sig { returns(T::Array[[Dependabot::Version, T::Hash[String, T.nilable(String)]]]) }
        def possible_previous_versions_with_details
          possible_previous_releases.map do |r|
            [r.version, { "deprecated" => r.yanked? ? "yanked" : nil }]
          end
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          Dependabot::Experiments.enabled?(:enable_cooldown_for_bun)
        end

        private

        sig { params(_block: T.untyped).returns(T.nilable(Dependabot::Version)) }
        def with_custom_registry_rescue(&_block)
          yield
        rescue Excon::Error::Socket, Excon::Error::Timeout, RegistryError
          raise unless package_fetcher.custom_registry?

          # Custom registries can be flaky. We don't want to make that
          # our problem, so quietly return `nil` here.
          nil
        end

        sig { returns(T::Boolean) }
        def valid_npm_details?
          !!package_details&.releases&.any?
        end

        sig { returns(T.nilable(Dependabot::Package::PackageRelease)) }
        def version_from_dist_tags # rubocop:disable Metrics/PerceivedComplexity
          dist_tags = package_details&.dist_tags
          return nil unless dist_tags

          dist_tag_req = dependency.requirements
                                   .find { |r| dist_tags.include?(r[:requirement]) }
                                   &.fetch(:requirement)

          releases = package_details&.releases

          releases = filter_by_cooldown(releases) if releases

          if dist_tag_req
            release = find_dist_tag_release(dist_tag_req, releases)
            return release if release && !release.yanked?
          end

          latest_release = find_dist_tag_release("latest", releases)

          return nil unless latest_release

          return latest_release if wants_latest_dist_tag?(latest_release.version) && !latest_release.yanked?

          nil
        end

        sig do
          params(
            dist_tag: T.nilable(String),
            releases: T.nilable(T::Array[Dependabot::Package::PackageRelease])
          )
            .returns(T.nilable(Dependabot::Package::PackageRelease))
        end
        def find_dist_tag_release(dist_tag, releases)
          dist_tags = package_details&.dist_tags
          return nil unless releases && dist_tags && dist_tag

          dist_tag_version = dist_tags[dist_tag]

          return nil unless dist_tag_version && !dist_tag_version.empty?

          release = releases.find { |r| r.version == Version.new(dist_tag_version) }

          release
        end

        sig { returns(T::Boolean) }
        def specified_dist_tag_requirement?
          dependency.requirements.any? do |req|
            next false if req[:requirement].nil?
            next false unless req[:requirement].match?(/^[A-Za-z]/)

            !req[:requirement].match?(/^v\d/i)
          end
        end

        sig do
          params(version: Dependabot::Version)
            .returns(T::Boolean)
        end
        def wants_latest_dist_tag?(version)
          return false if related_to_current_pre?(version) ^ version.prerelease?
          return false if current_version_greater_than?(version)
          return false if current_requirement_greater_than?(version)
          return false if ignore_requirements.any? { |r| r.satisfied_by?(version) }
          return false if yanked_version?(version)

          true
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def current_requirement_greater_than?(version)
          dependency.requirements.any? do |req|
            next false unless req[:requirement]

            req_version = req[:requirement].sub(/^\^|~|>=?/, "")
            next false unless version_class.correct?(req_version)

            version_class.new(req_version) > version
          end
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def related_to_current_pre?(version)
          current_version = dependency.numeric_version
          if current_version&.prerelease? &&
             current_version.release == version.release
            return true
          end

          dependency.requirements.any? do |req|
            next unless req[:requirement]&.match?(/\d-[A-Za-z]/)

            Bun::Requirement
              .requirements_array(req.fetch(:requirement))
              .any? do |r|
                r.requirements.any? { |a| a.last.release == version.release }
              end
          rescue Gem::Requirement::BadRequirementError
            false
          end
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def current_version_greater_than?(version)
          return false unless dependency.numeric_version

          T.must(dependency.numeric_version) > version
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def yanked_version?(version)
          package_fetcher.yanked?(version)
        end
      end

      class LatestVersionFinder # rubocop:disable Metrics/ClassLength
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          raise_on_ignored: false
        )
          @dependency          = dependency
          @credentials         = credentials
          @dependency_files    = dependency_files
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories

          @possible_previous_versions_with_details = T.let(nil, T.nilable(T::Array[T::Array[T.untyped]]))
          @yanked = T.let({}, T::Hash[Version, T.nilable(T::Boolean)])
          @npm_details = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
          @registry_finder = T.let(nil, T.nilable(Package::RegistryFinder))
          @version_endpoint_working = T.let(nil, T.nilable(T::Boolean))
        end

        sig { returns(T.nilable(Version)) }
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

        sig { returns(T.nilable(Version)) }
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

        sig { returns(T.nilable(Version)) }
        def lowest_security_fix_version
          return unless valid_npm_details?

          secure_versions =
            if specified_dist_tag_requirement?
              [version_from_dist_tags].compact
            else
              possible_versions(filter_ignored: false)
            end

          secure_versions = Dependabot::UpdateCheckers::VersionFilters
                            .filter_vulnerable_versions(
                              secure_versions,
                              security_advisories
                            )
          secure_versions = filter_ignored_versions(secure_versions)
          secure_versions = filter_lower_versions(secure_versions)

          secure_versions.reverse.find { |version| !yanked?(version) }
        rescue Excon::Error::Socket, Excon::Error::Timeout
          raise if dependency_registry == "registry.npmjs.org"
          # Sometimes custom registries are flaky. We don't want to make that
          # our problem, so we quietly return `nil` here.
        end

        sig { returns(T::Array[T::Array[T.untyped]]) }
        def possible_previous_versions_with_details # rubocop:disable Metrics/PerceivedComplexity
          return @possible_previous_versions_with_details if @possible_previous_versions_with_details

          @possible_previous_versions_with_details =
            npm_details&.fetch("versions", {})
                       &.transform_keys { |k| version_class.new(k) }
                       &.reject do |v, _|
              v.prerelease? && !related_to_current_pre?(v)
            end&.sort_by(&:first)&.reverse
          @possible_previous_versions_with_details
        end

        sig do
          params(filter_ignored: T::Boolean)
            .returns(T::Array[T::Array[T.untyped]])
        end
        def possible_versions_with_details(filter_ignored: true)
          versions = possible_previous_versions_with_details
                     .reject { |_, details| details["deprecated"] }

          return filter_ignored_versions(versions) if filter_ignored

          versions
        end

        sig do
          params(filter_ignored: T::Boolean)
            .returns(T::Array[Version])
        end
        def possible_versions(filter_ignored: true)
          possible_versions_with_details(filter_ignored: filter_ignored)
            .map(&:first)
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files
        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions
        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(T::Boolean) }
        def valid_npm_details?
          !npm_details&.fetch("dist-tags", nil).nil?
        end

        sig { params(versions_array: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def filter_ignored_versions(versions_array)
          filtered = versions_array.reject do |v, _|
            ignore_requirements.any? { |r| r.satisfied_by?(v) }
          end

          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise AllVersionsIgnored
          end

          if versions_array.count > filtered.count
            diff = versions_array.count - filtered.count
            Dependabot.logger.info("Filtered out #{diff} ignored versions")
          end

          filtered
        end

        sig { params(versions_array: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def filter_out_of_range_versions(versions_array)
          reqs = dependency.requirements.filter_map do |r|
            Bun::Requirement.requirements_array(r.fetch(:requirement))
          end

          versions_array
            .select { |v| reqs.all? { |r| r.any? { |o| o.satisfied_by?(v) } } }
        end

        sig { params(versions_array: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def filter_lower_versions(versions_array)
          return versions_array unless dependency.numeric_version

          versions_array
            .select { |version, _| version > dependency.numeric_version }
        end

        sig { returns(T.nilable(Version)) }
        def version_from_dist_tags
          details = npm_details

          return nil unless details

          dist_tags = details["dist-tags"].keys

          # Check if a dist tag was specified as a requirement. If it was, and
          # it exists, use it.
          dist_tag_req = dependency.requirements
                                   .find { |r| dist_tags.include?(r[:requirement]) }
                                   &.fetch(:requirement)

          if dist_tag_req
            tag_vers =
              version_class.new(details["dist-tags"][dist_tag_req])
            return tag_vers unless yanked?(tag_vers)
          end

          # Use the latest dist tag unless there's a reason not to
          return nil unless details["dist-tags"]["latest"]

          latest = version_class.new(details["dist-tags"]["latest"])

          wants_latest_dist_tag?(latest) ? latest : nil
        end

        sig { params(version: Version).returns(T::Boolean) }
        def related_to_current_pre?(version)
          current_version = dependency.numeric_version
          if current_version&.prerelease? &&
             current_version.release == version.release
            return true
          end

          dependency.requirements.any? do |req|
            next unless req[:requirement]&.match?(/\d-[A-Za-z]/)

            Bun::Requirement
              .requirements_array(req.fetch(:requirement))
              .any? do |r|
                r.requirements.any? { |a| a.last.release == version.release }
              end
          rescue Gem::Requirement::BadRequirementError
            false
          end
        end

        sig { returns(T::Boolean) }
        def specified_dist_tag_requirement?
          dependency.requirements.any? do |req|
            next false if req[:requirement].nil?
            next false unless req[:requirement].match?(/^[A-Za-z]/)

            !req[:requirement].match?(/^v\d/i)
          end
        end

        sig { params(latest_version: Version).returns(T::Boolean) }
        def wants_latest_dist_tag?(latest_version)
          ver = latest_version
          return false if related_to_current_pre?(ver) ^ ver.prerelease?
          return false if current_version_greater_than?(ver)
          return false if current_requirement_greater_than?(ver)
          return false if ignore_requirements.any? { |r| r.satisfied_by?(ver) }
          return false if yanked?(ver)

          true
        end

        sig { params(version: Version).returns(T::Boolean) }
        def current_version_greater_than?(version)
          return false unless dependency.numeric_version

          T.must(dependency.numeric_version) > version
        end

        sig { params(version: Version).returns(T::Boolean) }
        def current_requirement_greater_than?(version)
          dependency.requirements.any? do |req|
            next false unless req[:requirement]

            req_version = req[:requirement].sub(/^\^|~|>=?/, "")
            next false unless version_class.correct?(req_version)

            version_class.new(req_version) > version
          end
        end

        sig { params(version: Version).returns(T::Boolean) }
        def yanked?(version)
          return @yanked[version] || false if @yanked.key?(version)

          @yanked[version] =
            begin
              if dependency_registry == "registry.npmjs.org"
                status = Dependabot::RegistryClient.head(
                  url: registry_finder.tarball_url(version),
                  headers: registry_auth_headers
                ).status
              else
                status = Dependabot::RegistryClient.get(
                  url: dependency_url + "/#{version}",
                  headers: registry_auth_headers
                ).status

                if status == 404
                  # Some registries don't handle escaped package names properly
                  status = Dependabot::RegistryClient.get(
                    url: dependency_url.gsub("%2F", "/") + "/#{version}",
                    headers: registry_auth_headers
                  ).status
                end
              end

              version_not_found = status == 404
              version_not_found && version_endpoint_working?
            rescue Excon::Error::Timeout, Excon::Error::Socket
              # Give the benefit of the doubt if the registry is playing up
              false
            end

          @yanked[version] || false
        end

        sig { returns(T.nilable(T::Boolean)) }
        def version_endpoint_working?
          return true if dependency_registry == "registry.npmjs.org"

          return @version_endpoint_working if @version_endpoint_working

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
          @version_endpoint_working
        end

        sig { returns(T.nilable(T::Hash[String, T.untyped])) }
        def npm_details
          return @npm_details if @npm_details

          @npm_details = fetch_npm_details
        end

        sig { returns(T.nilable(T::Hash[String, T.untyped])) }
        def fetch_npm_details
          npm_response = fetch_npm_response

          return nil unless npm_response

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

        sig { returns(T.nilable(Excon::Response)) }
        def fetch_npm_response
          response = Dependabot::RegistryClient.get(
            url: dependency_url,
            headers: registry_auth_headers
          )
          return response unless response.status == 500
          return response unless registry_auth_headers["Authorization"]

          auth = registry_auth_headers["Authorization"]
          return response unless auth&.start_with?("Basic")

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
        rescue URI::InvalidURIError => e
          raise DependencyFileNotResolvable, e.message
        end

        sig { params(npm_response: Excon::Response).void }
        def check_npm_response(npm_response)
          return if git_dependency?

          if private_dependency_not_reachable?(npm_response)
            raise PrivateSourceAuthenticationFailure, dependency_registry
          end

          # handles scenario when private registry returns a server error 5xx
          if private_dependency_server_error?(npm_response)
            msg = "Server error #{npm_response.status} returned while accessing registry" \
                  " #{dependency_registry}."
            raise DependencyFileNotResolvable, msg
          end

          status = npm_response.status

          # handles issue when status 200 is returned from registry but with an invalid JSON object
          if status.to_s.start_with?("2") && response_invalid_json?(npm_response)
            msg = "Invalid JSON object returned from registry #{dependency_registry}."
            Dependabot.logger.warn("#{msg} Response body (truncated) : #{npm_response.body[0..500]}...")
            raise DependencyFileNotResolvable, msg
          end

          return if status.to_s.start_with?("2")

          # Ignore 404s from the registry for updates where a lockfile doesn't
          # need to be generated. The 404 won't cause problems later.
          return if status == 404 && dependency.version.nil?

          msg = "Got #{status} response with body #{npm_response.body}"
          raise RegistryError.new(status, msg)
        end

        sig { params(error: Exception).void }
        def raise_npm_details_error(error)
          raise if dependency_registry == "registry.npmjs.org"
          raise unless error.is_a?(Excon::Error::Timeout)

          raise PrivateSourceTimedOut, dependency_registry
        end

        sig { params(npm_response: Excon::Response).returns(T::Boolean) }
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

        sig { params(npm_response: Excon::Response).returns(T::Boolean) }
        def private_dependency_server_error?(npm_response)
          if [500, 501, 502, 503].include?(npm_response.status)
            Dependabot.logger.warn("#{dependency_registry} returned code #{npm_response.status} with " \
                                   "body #{npm_response.body}.")
            return true
          end
          false
        end

        sig { params(npm_response: Excon::Response).returns(T::Boolean) }
        def response_invalid_json?(npm_response)
          result = JSON.parse(npm_response.body)
          result.is_a?(Hash) || result.is_a?(Array)
          false
        rescue JSON::ParserError, TypeError
          true
        end

        sig { returns(String) }
        def dependency_url
          registry_finder.dependency_url
        end

        sig { returns(String) }
        def dependency_registry
          registry_finder.registry
        end

        sig { returns(T::Hash[String, String]) }
        def registry_auth_headers
          registry_finder.auth_headers
        end

        sig { returns(Package::RegistryFinder) }
        def registry_finder
          return @registry_finder if @registry_finder

          @registry_finder = Package::RegistryFinder.new(
            dependency: dependency,
            credentials: credentials,
            npmrc_file: npmrc_file
          )
          @registry_finder
        end

        sig { returns(T::Array[Dependabot::Requirement]) }
        def ignore_requirements
          ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
        end

        sig { returns(T.class_of(Version)) }
        def version_class
          Dependabot::Bun::Version
        end

        sig { returns(T.class_of(Requirement)) }
        def requirement_class
          Dependabot::Bun::Requirement
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def npmrc_file
          dependency_files.find { |f| f.name.end_with?(".npmrc") }
        end

        sig { returns(T::Boolean) }
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
