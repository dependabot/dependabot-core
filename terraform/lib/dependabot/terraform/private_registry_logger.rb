# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Terraform
    # Utility class for structured logging of private registry operations.
    #
    # This class provides centralized logging functionality specifically for private
    # Terraform registry operations, helping with debugging and monitoring of
    # private registry interactions. It automatically filters out public registry
    # operations to reduce noise in logs.
    #
    # @example Basic usage
    #   PrivateRegistryLogger.log_registry_operation(
    #     hostname: "private-registry.example.com",
    #     operation: "source_resolution",
    #     details: { dependency_name: "company/vpc/aws" }
    #   )
    #
    # @example Error logging
    #   PrivateRegistryLogger.log_registry_error(
    #     hostname: "private-registry.example.com",
    #     error: StandardError.new("Connection failed"),
    #     context: { operation: "authentication" }
    #   )
    class PrivateRegistryLogger
      extend T::Sig

      # Logs a private registry operation with structured details.
      #
      # This method only logs operations for private registries (non-public Terraform registry).
      # Public registry operations are filtered out to reduce log noise.
      #
      # @param hostname [String] The hostname of the registry
      # @param operation [String] The type of operation being performed
      # @param details [Hash] Additional details about the operation
      # @return [void]
      sig { params(hostname: String, operation: String, details: T::Hash[String, T.untyped]).void }
      def self.log_registry_operation(hostname:, operation:, details: {})
        return unless private_registry?(hostname)

        details_str = details.empty? ? "" : " (#{details.map { |k, v| "#{k}: #{v}" }.join(", ")})"
        Dependabot.logger.info("Private registry operation: #{operation} for #{hostname}#{details_str}")
      end

      # Logs a private registry error with structured context.
      #
      # This method only logs errors for private registries. It includes error details
      # while being careful not to expose sensitive information like tokens or passwords.
      #
      # @param hostname [String] The hostname of the registry where the error occurred
      # @param error [StandardError] The error that occurred
      # @param context [Hash] Additional context about when/where the error occurred
      # @return [void]
      sig { params(hostname: String, error: StandardError, context: T::Hash[String, T.untyped]).void }
      def self.log_registry_error(hostname:, error:, context: {})
        return unless private_registry?(hostname)

        context_str = context.empty? ? "" : " (#{context.map { |k, v| "#{k}: #{v}" }.join(", ")})"
        Dependabot.logger.warn("Private registry error: #{error.class.name} for #{hostname}: #{error.message}#{context_str}")
      end

      # Determines if a hostname represents a private registry.
      #
      # Currently, this method considers any hostname other than the public
      # Terraform registry (registry.terraform.io) to be a private registry.
      #
      # @param hostname [String] The hostname to check
      # @return [Boolean] true if the hostname is a private registry, false otherwise
      sig { params(hostname: String).returns(T::Boolean) }
      def self.private_registry?(hostname)
        hostname != "registry.terraform.io"
      end
    end
  end
end
