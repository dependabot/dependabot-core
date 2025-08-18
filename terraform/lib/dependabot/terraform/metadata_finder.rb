# typed: strict
# frozen_string_literal: true

require "excon"
require "json"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/metadata_finders/base/changelog_finder"
require "dependabot/metadata_finders/base/release_finder"
require "dependabot/terraform/registry_client"
require "dependabot/terraform/private_registry_logger"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Terraform
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      # Override changelog_text to use enhanced credentials for private registries.
      #
      # For private registry dependencies, this method ensures that the appropriate
      # credentials are passed to the ChangelogFinder, enabling access to private
      # source repositories.
      #
      # @return [String, nil] The changelog text or nil if not found/accessible
      sig { override.returns(T.nilable(String)) }
      def changelog_text
        return super unless dependency.source_type == "registry"

        @changelog_finder ||= T.let(
          Dependabot::MetadataFinders::Base::ChangelogFinder.new(
            dependency: dependency,
            source: source,
            credentials: enhanced_credentials_for_changelog,
            suggested_changelog_url: suggested_changelog_url
          ),
          T.nilable(Dependabot::MetadataFinders::Base::ChangelogFinder)
        )
        @changelog_finder.changelog_text
      end

      # Override releases_text to use enhanced credentials for private registries.
      #
      # For private registry dependencies, this method ensures that the appropriate
      # credentials are passed to the ReleaseFinder, enabling access to private
      # source repositories for GitHub releases.
      #
      # @return [String, nil] The releases text or nil if not found/accessible
      sig { override.returns(T.nilable(String)) }
      def releases_text
        return super unless dependency.source_type == "registry"

        @release_finder ||= T.let(
          Dependabot::MetadataFinders::Base::ReleaseFinder.new(
            dependency: dependency,
            source: source,
            credentials: enhanced_credentials_for_changelog
          ),
          T.nilable(Dependabot::MetadataFinders::Base::ReleaseFinder)
        )
        @release_finder.releases_text
      end

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        case new_source_type
        when "git" then find_source_from_git_url
        when "registry", "provider" then find_source_from_registry_details
        else raise "Unexpected source type: #{new_source_type}"
        end
      end

      sig { returns(T.nilable(String)) }
      def new_source_type
        dependency.source_type
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_git_url
        info = dependency.requirements.filter_map { |r| r[:source] }.first

        url = info[:url] || info.fetch("url")
        Source.from_url(url)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_registry_details
        info = dependency.requirements.filter_map { |r| r[:source] }.first
        hostname = info[:registry_hostname] || info["registry_hostname"]

        PrivateRegistryLogger.log_registry_operation(
          hostname: hostname,
          operation: "metadata_finder_source_lookup",
          details: {
            dependency_name: dependency.name,
            dependency_version: dependency.version
          }
        )

        begin
          registry_client = RegistryClient.new(hostname: hostname, credentials: credentials)
          source = registry_client.source(dependency: dependency)

          if source
            validated_source = validate_source_access(source, hostname)
            PrivateRegistryLogger.log_registry_operation(
              hostname: hostname,
              operation: "metadata_finder_source_resolved",
              details: {
                dependency_name: dependency.name,
                source_url: source.url,
                source_accessible: !validated_source.nil?
              }
            )
            validated_source
          else
            PrivateRegistryLogger.log_registry_operation(
              hostname: hostname,
              operation: "metadata_finder_no_source",
              details: {
                dependency_name: dependency.name,
                reason: "registry_returned_nil"
              }
            )
            nil
          end
        rescue Dependabot::PrivateSourceAuthenticationFailure => e
          PrivateRegistryLogger.log_registry_error(
            hostname: hostname,
            error: e,
            context: {
              operation: "metadata_finder_source_lookup",
              dependency_name: dependency.name,
              error_type: "authentication_failure"
            }
          )
          # Re-raise authentication failures as they should be handled by the caller
          raise
        rescue StandardError => e
          PrivateRegistryLogger.log_registry_error(
            hostname: hostname,
            error: e,
            context: {
              operation: "metadata_finder_source_lookup",
              dependency_name: dependency.name,
              error_type: "unexpected_error"
            }
          )
          # For other errors, return nil to allow graceful degradation
          nil
        end
      end

      # Validates that a resolved source is accessible with current credentials.
      #
      # Currently, this method assumes that if a source was returned by the registry,
      # it should be accessible. In the future, this could be enhanced to actually
      # test source accessibility with the current credentials.
      #
      # @param source [Dependabot::Source] The source to validate
      # @param hostname [String] The registry hostname for logging context
      # @return [Dependabot::Source, nil] The source if valid, nil if not accessible
      sig { params(source: Dependabot::Source, hostname: String).returns(T.nilable(Dependabot::Source)) }
      def validate_source_access(source, hostname)
        # For now, we'll assume the source is accessible if it was returned by the registry
        # In the future, this could be enhanced to actually test source accessibility
        # with the current credentials

        PrivateRegistryLogger.log_registry_operation(
          hostname: hostname,
          operation: "source_validation",
          details: {
            source_url: source.url,
            source_provider: source.provider,
            validation_result: "assumed_accessible"
          }
        )

        source
      end

      # Override source method to add logging for private registries.
      #
      # This method extends the base class source method to add structured logging
      # for private registry operations, helping with debugging and monitoring.
      # Public registry operations are not logged to reduce noise.
      #
      # @return [Dependabot::Source, nil] The resolved source or nil if not found
      sig { returns(T.nilable(Dependabot::Source)) }
      def source
        result = super

        if result && dependency.source_type == "registry"
          info = dependency.requirements.filter_map { |r| r[:source] }.first
          hostname = info[:registry_hostname] || info["registry_hostname"]

          PrivateRegistryLogger.log_registry_operation(
            hostname: hostname,
            operation: "metadata_finder_final_source",
            details: {
              dependency_name: dependency.name,
              source_url: result.url,
              source_provider: result.provider,
              has_credentials: !credentials.empty?
            }
          )
        end

        result
      end

      # Filters and contextualizes credentials for source repository access.
      #
      # This method filters the available credentials to include only those that
      # are relevant for accessing the source repository. It includes git source
      # credentials for repository access and is used by both changelog and release
      # finding functionality.
      #
      # @return [Array<Dependabot::Credential>] Filtered credentials for source access
      sig { returns(T::Array[Dependabot::Credential]) }
      def enhanced_credentials_for_changelog
        return credentials unless source

        # For private registries, filter credentials to include those relevant
        # for both the registry and the source repository
        source_host = T.must(source).hostname
        registry_info = dependency.requirements.filter_map { |r| r[:source] }.first
        registry_hostname = registry_info[:registry_hostname] || registry_info["registry_hostname"]

        relevant_credentials = credentials.select do |cred|
          case cred["type"]
          when "git_source"
            # Include git source credentials that match the source repository host
            cred["host"] == source_host
          when "terraform_registry"
            # Include terraform registry credentials for the registry hostname
            cred["host"] == registry_hostname
          else
            # Include other credential types that might be relevant
            true
          end
        end

        PrivateRegistryLogger.log_registry_operation(
          hostname: registry_hostname,
          operation: "credential_filtering_for_changelog",
          details: {
            source_host: source_host,
            registry_hostname: registry_hostname,
            total_credentials: credentials.length,
            relevant_credentials: relevant_credentials.length,
            credential_types: relevant_credentials.map { |c| c["type"] }.uniq
          }
        )

        relevant_credentials
      end

      # Filters and contextualizes credentials for source repository access.
      #
      # This method filters the available credentials to include only those that
      # are relevant for accessing the source repository. It includes git source
      # credentials for repository access and terraform registry credentials for
      # the specific hostname.
      #
      # @param source_hostname [String] The hostname to filter credentials for
      # @return [Array<Dependabot::Credential>] Filtered credentials relevant to the hostname
      sig { params(source_hostname: String).returns(T::Array[Dependabot::Credential]) }
      def enhanced_credentials_for_source(source_hostname)
        # Filter credentials to include relevant ones for the source repository
        relevant_credentials = credentials.select do |cred|
          case cred["type"]
          when "git_source"
            # Include git source credentials that might be needed for source repository access
            true
          when "terraform_registry"
            # Include terraform registry credentials for the specific hostname
            cred["host"] == source_hostname
          else
            # Include other credential types that might be relevant
            true
          end
        end

        PrivateRegistryLogger.log_registry_operation(
          hostname: source_hostname,
          operation: "credential_filtering",
          details: {
            total_credentials: credentials.length,
            relevant_credentials: relevant_credentials.length,
            credential_types: relevant_credentials.map { |c| c["type"] }.uniq
          }
        )

        relevant_credentials
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("terraform", Dependabot::Terraform::MetadataFinder)
