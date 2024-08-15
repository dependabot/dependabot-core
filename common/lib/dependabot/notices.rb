# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/package_manager"

module Dependabot
  class Notice
    extend T::Sig

    sig { returns(String) }
    attr_reader :mode, :type, :package_manager_name, :message, :markdown

    # Initializes a new Notice object.
    # @param mode [String] The mode of the notice (e.g., "WARN", "ERROR").
    # @param type [String] The type of the notice (e.g., "bundler_deprecated_warn").
    # @param package_manager_name [String] The name of the package manager (e.g., "bundler").
    # @param message [String] The main message of the notice.
    # @param markdown [String] The markdown formatted message.
    sig do
      params(
        mode: String,
        type: String,
        package_manager_name: String,
        message: String,
        markdown: String
      ).void
    end
    def initialize(mode:, type:, package_manager_name:, message: "", markdown: "")
      @mode = mode
      @type = type
      @package_manager_name = package_manager_name
      @message = message
      @markdown = markdown
    end

    # Converts the Notice object to a hash.
    # @return [Hash] The hash representation of the notice.
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      {
        mode: @mode,
        type: @type,
        package_manager_name: @package_manager_name,
        message: @message,
        markdown: @markdown
      }
    end

    # Generates a message for supported versions.
    # @param supported_versions [Array<Dependabot::Version>, nil] The supported versions of the package manager.
    # @param support_later_versions [Boolean] Whether later versions are supported.
    # @return [String, nil] The generated message or nil if no supported versions are provided.
    sig do
      params(
        supported_versions: T.nilable(T::Array[Dependabot::Version]),
        support_later_versions: T::Boolean
      ).returns(String)
    end
    def self.generate_supported_versions_message(supported_versions, support_later_versions)
      return "" unless supported_versions&.any?

      versions_string = supported_versions.map { |version| "v#{version}" }.join(", ")

      later_message = support_later_versions ? " or later" : ""

      return "Please upgrade to version `#{versions_string}`#{later_message}." if supported_versions.count == 1

      "Please upgrade to one of the following versions: #{versions_string}#{later_message}."
    end

    # Generates a support notice for the given package manager.
    # @param package_manager [PackageManagerBase] The package manager object.
    # @return [Notice, nil] The generated notice or nil if no notice is applicable.
    sig do
      params(
        package_manager: PackageManagerBase
      ).returns(T.nilable(Notice))
    end
    def self.generate_support_notice(package_manager)
      deprecation_notice = generate_pm_deprecation_notice(package_manager)

      return deprecation_notice if deprecation_notice

      generate_pm_unsupported_notice(package_manager)
    end

    # Generates a deprecation notice for the given package manager.
    # @param package_manager [PackageManagerBase] The package manager object.
    # @return [Notice, nil] The generated deprecation notice or nil if the package manager is not deprecated.
    sig do
      params(
        package_manager: PackageManagerBase
      ).returns(T.nilable(Notice))
    end
    def self.generate_pm_deprecation_notice(package_manager)
      return nil unless package_manager.deprecated?

      mode = "WARN"
      supported_versions_message = generate_supported_versions_message(
        package_manager.supported_versions,
        package_manager.support_later_versions?
      )
      notice_type = "#{package_manager.name}_deprecated_#{mode.downcase}"
      message = "Dependabot will stop supporting `#{package_manager.name}` `v#{package_manager.version}`!"
      ## Create a warning markdown message
      markdown = "> [!WARNING]\n"
      ## Add the deprecation warning to the message
      markdown += "> #{message}\n\n"

      ## Add the supported versions to the message
      unless supported_versions_message.empty?
        message += "\n#{supported_versions_message}\n"
        markdown += "> #{supported_versions_message}\n\n"
      end

      Notice.new(
        mode: mode,
        type: notice_type,
        package_manager_name: package_manager.name,
        message: message,
        markdown: markdown
      )
    end

    # Generates an unsupported notice for the given package manager.
    # @param package_manager [PackageManagerBase] The package manager object.
    # @return [Notice, nil] The generated unsupported notice or nil if the package manager is not unsupported.
    sig do
      params(
        package_manager: PackageManagerBase
      ).returns(T.nilable(Notice))
    end
    def self.generate_pm_unsupported_notice(package_manager)
      return nil unless package_manager.unsupported?

      mode = "ERROR"
      supported_versions_message = generate_supported_versions_message(
        package_manager.supported_versions,
        package_manager.support_later_versions?
      )
      notice_type = "#{package_manager.name}_unsupported_#{mode.downcase}"
      message = "Dependabot no longer supports `#{package_manager.name}` `v#{package_manager.version}`!"
      ## Create an error markdown message
      markdown = "> [IMPORTANT]\n"
      ## Add the error message to the message
      markdown += "> #{message}\n\n"

      ## Add the supported versions to the message
      unless supported_versions_message.empty?
        message += "\n#{supported_versions_message}\n"
        markdown += "> #{supported_versions_message}\n\n"
      end

      Notice.new(
        mode: mode,
        type: notice_type,
        package_manager_name: package_manager.name,
        message: message,
        markdown: markdown
      )
    end
  end
end
