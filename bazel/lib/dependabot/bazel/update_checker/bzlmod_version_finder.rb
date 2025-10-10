# typed: strict
# frozen_string_literal: true

require "dependabot/bazel/version"
require "dependabot/shared_helpers"
require "excon"
require "json"

module Dependabot
  module Bazel
    class BzlmodVersionFinder
      extend T::Sig

      BCR_BASE_URL = "https://bcr.bazel.build"
      BCR_API_URL = "https://registry.bazel.build"

      sig do
        params(
          dependency: Dependabot::Dependency,
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          ignored_versions: T::Array[String]
        ).void
      end
      def initialize(dependency:, dependency_files:, credentials:, ignored_versions: [])
        @dependency = dependency
        @dependency_files = dependency_files
        @credentials = credentials
        @ignored_versions = ignored_versions
      end

      sig { returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        return nil unless bzlmod_dependency?

        fetch_latest_version_from_bcr
      end

      sig { returns(T::Boolean) }
      def can_update?
        latest = latest_version
        return false unless latest
        return false if latest == @dependency.version

        # Check if the latest version is not in ignored versions
        !ignored_versions.include?(latest.to_s)
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return @dependency.requirements unless can_update?

        latest = latest_version
        return @dependency.requirements unless latest

        # Update MODULE.bazel bazel_dep() declaration
        @dependency.requirements.map do |requirement|
          if requirement[:file]&.end_with?("MODULE.bazel")
            requirement.merge(requirement: latest.to_s)
          else
            requirement
          end
        end
      end

      sig { returns(T::Array[String]) }
      def available_versions
        @available_versions ||= T.let(fetch_available_versions_from_bcr, T.nilable(T::Array[String]))
      end

      private

      sig { returns(T.nilable(T.any(String, Gem::Version))) }
      def fetch_latest_version_from_bcr
        versions = available_versions
        return nil if versions.empty?

        # Filter out ignored versions and pre-release versions if needed
        filtered_versions = filter_versions(versions)
        return nil if filtered_versions.empty?

        # Return the latest semantic version
        latest_version_string = filtered_versions.max_by do |version_string|
          next Version.new("0.0.0") unless Version.correct?(version_string)

          Version.new(version_string)
        end

        return nil unless latest_version_string && Version.correct?(latest_version_string)

        Version.new(latest_version_string)
      end

      sig { returns(T::Array[String]) }
      def fetch_available_versions_from_bcr
        # Try the new registry API first, fallback to old BCR format
        versions = fetch_versions_from_registry_api || fetch_versions_from_bcr_metadata || []
        versions.compact.uniq.sort
      rescue Excon::Error, JSON::ParserError => e
        Dependabot.logger.warn("Failed to fetch versions from BCR for #{@dependency.name}: #{e.message}")
        []
      end

      sig { returns(T.nilable(T::Array[String])) }
      def fetch_versions_from_registry_api
        url = "#{BCR_API_URL}/modules/#{@dependency.name}"

        response = Excon.get(
          url,
          headers: {
            "Accept" => "application/json",
            "User-Agent" => "Dependabot"
          },
          idempotent: true,
          **SharedHelpers.excon_defaults
        )

        return nil unless response.status == 200

        data = JSON.parse(response.body)
        return nil unless data.is_a?(Hash)

        versions = data.dig("versions")
        return nil unless versions.is_a?(Array)

        versions.filter_map do |version_info|
          next unless version_info.is_a?(Hash)

          version = version_info["version"]
          next unless version.is_a?(String)

          # Skip yanked versions
          next if version_info["yanked"] == true

          version
        end
      rescue Excon::Error::NotFound
        # Module not found in BCR
        nil
      end

      sig { returns(T.nilable(T::Array[String])) }
      def fetch_versions_from_bcr_metadata
        # Fallback: try to fetch from BCR metadata endpoint
        url = "#{BCR_BASE_URL}/modules/#{@dependency.name}/metadata.json"

        response = Excon.get(
          url,
          headers: {
            "Accept" => "application/json",
            "User-Agent" => "Dependabot"
          },
          idempotent: true,
          **SharedHelpers.excon_defaults
        )

        return nil unless response.status == 200

        data = JSON.parse(response.body)
        return nil unless data.is_a?(Hash)

        versions = data.dig("versions")
        return nil unless versions.is_a?(Array)

        versions.filter_map do |version|
          version.is_a?(String) ? version : nil
        end
      rescue Excon::Error::NotFound
        # Module not found in BCR
        nil
      end

      sig { params(versions: T::Array[String]).returns(T::Array[String]) }
      def filter_versions(versions)
        filtered = versions.reject do |version|
          # Skip ignored versions
          next true if ignored_versions.include?(version)

          # Skip invalid versions
          next true unless Version.correct?(version)

          false
        end

        # Filter out pre-release versions unless we're already on a pre-release
        if @dependency.version && Version.correct?(@dependency.version)
          current_version = Version.new(@dependency.version)
          unless current_version.prerelease?
            filtered = filtered.reject do |version|
              Version.new(version).prerelease?
            end
          end
        end

        filtered
      end

      sig { returns(T::Array[String]) }
      def ignored_versions
        @ignored_versions
      end

      sig { returns(T::Boolean) }
      def bzlmod_dependency?
        module_files.any? do |file|
          content = file.content
          next false unless content

          # Look for bazel_dep() declaration with this dependency name
          content.match?(/bazel_dep\(\s*name\s*=\s*"#{Regexp.escape(@dependency.name)}"/)
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def module_files
        @module_files ||= T.let(
          @dependency_files.select { |f| f.name.end_with?("MODULE.bazel") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def dependency_declaration
        @dependency_declaration ||= T.let(
          begin
            declaration = {}
            module_files.each do |file|
              content = file.content
              next unless content

              # Extract the full bazel_dep() declaration for this dependency
              match = content.match(
                /bazel_dep\(\s*name\s*=\s*"#{Regexp.escape(@dependency.name)}"[^)]*\)/m
              )
              if match
                declaration[:file] = file.name
                declaration[:declaration] = match[0]
                declaration_text = T.must(match[0])
                declaration[:attributes] = parse_bazel_dep_attributes(declaration_text)
                break
              end
            end
            declaration
          end,
          T.nilable(T::Hash[Symbol, T.untyped])
        )
      end

      sig { params(declaration_text: String).returns(T::Hash[Symbol, T.untyped]) }
      def parse_bazel_dep_attributes(declaration_text)
        attributes = {}

        # Extract name
        name_match = declaration_text.match(/name\s*=\s*"([^"]+)"/)
        attributes[:name] = name_match[1] if name_match

        # Extract version
        version_match = declaration_text.match(/version\s*=\s*"([^"]+)"/)
        attributes[:version] = version_match[1] if version_match

        # Extract dev_dependency flag
        dev_dep_match = declaration_text.match(/dev_dependency\s*=\s*(True|False)/i)
        if dev_dep_match
          match_value = T.must(dev_dep_match[1])
          attributes[:dev_dependency] = match_value.downcase == "true"
        end

        # Extract repo_name
        repo_name_match = declaration_text.match(/repo_name\s*=\s*"([^"]+)"/)
        attributes[:repo_name] = repo_name_match[1] if repo_name_match

        attributes
      end

      sig { returns(String) }
      def updated_declaration_text
        return "" unless can_update?

        latest = latest_version
        return "" unless latest

        original_attrs = dependency_declaration[:attributes] || {}

        # Build the updated bazel_dep() declaration
        parts = ["name = \"#{@dependency.name}\""]
        parts << "version = \"#{latest}\""

        # Preserve other attributes
        if original_attrs[:dev_dependency]
          parts << "dev_dependency = True"
        end

        if original_attrs[:repo_name]
          parts << "repo_name = \"#{original_attrs[:repo_name]}\""
        end

        "bazel_dep(#{parts.join(', ')})"
      end

      sig { returns(T::Boolean) }
      def supports_version_constraints?
        # Bzlmod currently doesn't support version ranges like npm
        # Each bazel_dep() specifies an exact version
        false
      end
    end
  end
end
