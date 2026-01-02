# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/opam/version"
require "dependabot/opam/requirement"
require "dependabot/shared_helpers"
require "excon"

module Dependabot
  module Opam
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/version_resolver"

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version
        @latest_version ||= T.let(
          begin
            version_resolver.latest_version
          end,
          T.nilable(T.any(String, Dependabot::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version
        return latest_version if dependency.requirements.empty?

        # Find the highest version that satisfies all requirements
        all_versions = fetch_all_versions
        return latest_version if all_versions.empty?

        dependency.requirements.each do |req|
          requirement_string = req[:requirement]
          next if requirement_string.nil? || requirement_string.strip.empty?

          begin
            requirement = Requirement.requirements_array(requirement_string)
            all_versions = all_versions.select do |version|
              # Use Opam::Version which supports Debian versioning (~ prefix)
              requirement.all? { |r| r.satisfied_by?(version) }
            end
          rescue Gem::Requirement::BadRequirementError
            # If we can't parse the requirement, skip filtering
            next
          end
        end

        all_versions.max
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        # Security advisories not yet supported for opam
        nil
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        dependency.requirements.map do |req|
          updated_req = req.dup
          updated_req[:requirement] = updated_version_requirement_string(req)
          updated_req
        end
      end

      private

      sig { returns(T::Array[Dependabot::Opam::Version]) }
      def fetch_all_versions
        package_name = dependency.name
        url = "https://opam.ocaml.org/packages/#{package_name}/"

        begin
          response = Excon.get(
            url,
            headers: { "Accept" => "application/json" },
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          return [] unless response.status == 200

          parse_versions_from_html(response.body)
        rescue Excon::Error::Timeout, Excon::Error::Socket
          []
        end
      end

      sig { params(html: String).returns(T::Array[Dependabot::Opam::Version]) }
      def parse_versions_from_html(html)
        versions = []
        package_name = dependency.name

        # Extract versions from href links: href="../package-name/package-name.version/"
        # This pattern matches version directory links, including versions with 'v' prefix
        escaped_name = Regexp.escape(package_name)
        pattern = %r{(?:href|src)="[^"]*#{escaped_name}/#{escaped_name}\.([v]?[0-9][^"/]*)/?"}i
        html.scan(pattern) do |match|
          version_string = match[0]
          next unless valid_version?(version_string)

          versions << Version.new(version_string)
        end

        # Also extract current/latest version from title-group (not in dropdown or dependencies)
        # Pattern: <h2>PACKAGENAME<span class="title-group">version...<span class="package-version">X.Y.Z</span>
        # More specific to avoid matching versions from Dependencies section
        title_pattern = %r{
          <h2>#{escaped_name}<span[^>]*class="title-group"[^>]*>.*?
          <span\sclass="package-version">([v]?[0-9][^<]+)</span>
        }mix
        title_match = html.match(title_pattern)
        if title_match
          version_string = title_match[1]
          versions << Version.new(version_string) if valid_version?(version_string)
        end

        versions.uniq.sort
      rescue StandardError
        []
      end

      sig { params(version_string: String).returns(T::Boolean) }
      def valid_version?(version_string)
        # Skip date-like versions (8 digits like 20230213, or YYYY.MM.DD format like 2025.02.17)
        return false if version_string.match?(/^\d{8}$/) # e.g. 20230213
        return false if version_string.match?(/^[12]\d{3}\.\d{1,2}\.\d{1,2}$/) # e.g. 2025.02.17
        return false unless version_string.include?(".")
        return false unless Version.correct?(version_string)

        true
      end

      sig { returns(VersionResolver) }
      def version_resolver
        @version_resolver ||= T.let(
          VersionResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          ),
          T.nilable(VersionResolver)
        )
      end

      sig { params(req: T::Hash[Symbol, T.untyped]).returns(String) }
      def updated_version_requirement_string(req)
        current_requirement = req[:requirement]
        return current_requirement if current_requirement.nil? || current_requirement.empty?

        latest = latest_version
        return current_requirement unless latest

        # Parse current requirement
        requirements = current_requirement.split("&").map(&:strip)

        # Separate version constraints from other constraints (filters, platform checks)
        # Only update version constraints, preserve everything else as-is
        updated_reqs = requirements.filter_map do |requirement|
          # Check if this is a version constraint (starts with operator, no prefix word)
          if requirement.match?(/^[><=!]+\s*"?\d+/)
            # This is a version constraint - update it
            update_version_in_requirement(requirement, latest.to_s)
          else
            # This is a filter/platform check - keep as-is
            requirement
          end
        end

        updated_reqs.join(" & ")
      end

      sig { params(requirement: String, new_version: String).returns(T.nilable(String)) }
      def update_version_in_requirement(requirement, new_version)
        match = requirement.match(/^([><=!]+)\s*"?([^"]+)"?$/)
        return requirement unless match

        operator = match[1]
        current_version_str = match[2].strip

        # Keep the same operator, update the version (with quotes per opam format)
        case operator
        when "=", "=="
          "= \"#{new_version}\""
        when ">="
          # For >= constraints, update to new minimum
          ">= \"#{new_version}\""
        when ">"
          "> \"#{new_version}\""
        when "<", "<="
          # For upper bounds, if new version exceeds current upper bound, REMOVE the constraint
          # to avoid contradictory constraints like: >= "0.37.0" & < "0.37.0"
          begin
            current_version = Version.new(current_version_str)
            new_ver = Version.new(new_version)
            if new_ver >= current_version
              # New version exceeds upper bound - remove this constraint by returning nil
              nil
            else
              # New version is below upper bound - keep original
              requirement
            end
          rescue ArgumentError
            # If version parsing fails, keep original requirement
            requirement
          end
        when "!="
          # Keep != constraints as-is
          requirement
        else
          requirement
        end
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # For simplicity, assume it's resolvable
        # In the future, this could check opam solver
        true
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        # Return just the current dependency
        [dependency]
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("opam", Dependabot::Opam::UpdateChecker)
