# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/package_manager"

module Dependabot
  class Notice
    module NoticeMode
      INFO = "INFO"
      WARN = "WARN"
      ERROR = "ERROR"
    end

    extend T::Sig

    sig { returns(String) }
    attr_reader :mode, :type, :package_manager_name, :title, :description

    sig { returns(T::Boolean) }
    attr_reader :show_in_pr, :show_alert

    # Initializes a new Notice object.
    # @param mode [String] The mode of the notice (e.g., "WARN", "ERROR").
    # @param type [String] The type of the notice (e.g., "bundler_deprecated_warn").
    # @param package_manager_name [String] The name of the package manager (e.g., "bundler").
    # @param title [String] The title of the notice.
    # @param description [String] The main description of the notice.
    # @param show_in_pr [Boolean] Whether the notice should be shown in a pull request.
    # @param show_alert [Boolean] Whether the notice should be shown in alerts.
    sig do
      params(
        mode: String,
        type: String,
        package_manager_name: String,
        title: String,
        description: String,
        show_in_pr: T::Boolean,
        show_alert: T::Boolean
      ).void
    end
    def initialize(
      mode:, type:, package_manager_name:,
      title: "", description: "",
      show_in_pr: false, show_alert: false
    )
      @mode = mode
      @type = type
      @package_manager_name = package_manager_name
      @title = title
      @description = description
      @show_in_pr = show_in_pr
      @show_alert = show_alert
    end

    # Converts the Notice object to a hash.
    # @return [Hash] The hash representation of the notice.
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      {
        mode: @mode,
        type: @type,
        package_manager_name: @package_manager_name,
        title: @title,
        description: @description,
        show_in_pr: @show_in_pr,
        show_alert: @show_alert
      }
    end

    # Generates a description for supported versions.
    # @param supported_versions [Array<Dependabot::Version>, nil] The supported versions of the package manager.
    # @param support_later_versions [Boolean] Whether later versions are supported.
    # @return [String, nil] The generated description or nil if no supported versions are provided.
    sig do
      params(
        supported_versions: T.nilable(T::Array[Dependabot::Version]),
        support_later_versions: T::Boolean
      ).returns(String)
    end
    def self.generate_supported_versions_description(supported_versions, support_later_versions)
      return "Please upgrade your package manager version" unless supported_versions&.any?

      versions_string = supported_versions.map { |version| "`v#{version}`" }

      versions_string[-1] = "or #{versions_string[-1]}" if versions_string.count > 1 && !support_later_versions

      versions_string = versions_string.join(", ")

      later_description = support_later_versions ? ", or later" : ""

      return "Please upgrade to version #{versions_string}#{later_description}." if supported_versions.count == 1

      "Please upgrade to one of the following versions: #{versions_string}#{later_description}."
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

      mode = NoticeMode::WARN
      supported_versions_description = generate_supported_versions_description(
        package_manager.supported_versions,
        package_manager.support_later_versions?
      )
      notice_type = "#{package_manager.name}_deprecated_warn"
      title = "Package manager deprecation notice"
      description = "Dependabot will stop supporting `#{package_manager.name} v#{package_manager.version}`!"

      ## Add the supported versions to the description
      description += "\n\n#{supported_versions_description}\n" unless supported_versions_description.empty?

      Notice.new(
        mode: mode,
        type: notice_type,
        package_manager_name: package_manager.name,
        title: title,
        description: description,
        show_in_pr: true,
        show_alert: true
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

      mode = NoticeMode::ERROR
      supported_versions_description = generate_supported_versions_description(
        package_manager.supported_versions,
        package_manager.support_later_versions?
      )
      notice_type = "#{package_manager.name}_unsupported_error"
      title = "Package manager unsupported notice"
      description = "Dependabot no longer supports `#{package_manager.name} v#{package_manager.version}`!"

      ## Add the supported versions to the description
      description += "\n\n#{supported_versions_description}\n" unless supported_versions_description.empty?

      Notice.new(
        mode: mode,
        type: notice_type,
        package_manager_name: package_manager.name,
        title: title,
        description: description,
        show_in_pr: true,
        show_alert: true
      )
    end

    sig { params(notice: Notice).returns(T.nilable(String)) }
    def self.markdown_from_description(notice)
      description = notice.description

      return if description.empty?

      markdown = "> [!#{markdown_mode(notice.mode)}]\n"
      # Log each non-empty line of the deprecation notice description
      description.each_line do |line|
        line = line.strip
        markdown += "> #{line}\n"
      end
      markdown
    end

    sig { params(mode: String).returns(String) }
    def self.markdown_mode(mode)
      case mode
      when NoticeMode::INFO
        "INFO"
      when NoticeMode::WARN
        "WARNING"
      when NoticeMode::ERROR
        "IMPORTANT"
      else
        "INFO"
      end
    end
  end
end
