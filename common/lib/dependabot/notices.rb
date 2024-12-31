# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"

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
    # @param version_manager_type [Symbol] The type of entity being deprecated i.e. :language or :package_manager
    # @return [String, nil] The generated description or nil if no supported versions are provided.
    sig do
      params(
        supported_versions: T.nilable(T::Array[Dependabot::Version]),
        support_later_versions: T::Boolean,
        version_manager_type: Symbol
      ).returns(String)
    end
    def self.generate_supported_versions_description(
      supported_versions, support_later_versions, version_manager_type = :package_manager
    )
      entity_text = version_manager_type == :language ? "language" : "package manager"
      return "Please upgrade your #{entity_text} version" unless supported_versions&.any?

      versions_string = supported_versions.map { |version| "`v#{version}`" }

      versions_string[-1] = "or #{versions_string[-1]}" if versions_string.count > 1 && !support_later_versions

      versions_string = versions_string.join(", ")

      later_description = support_later_versions ? ", or later" : ""

      return "Please upgrade to version #{versions_string}#{later_description}." if supported_versions.count == 1

      "Please upgrade to one of the following versions: #{versions_string}#{later_description}."
    end

    # Generates a deprecation notice for the given version manager.
    # @param version_manager [VersionManager] The version manager object.
    # @param version_manager_type [Symbol] The version manager type e.g. :language or :package_manager
    # @return [Notice, nil] The generated deprecation notice or nil if the version manager is not deprecated.
    sig do
      params(
        version_manager: Ecosystem::VersionManager,
        version_manager_type: Symbol
      ).returns(T.nilable(Notice))
    end
    def self.generate_deprecation_notice(version_manager, version_manager_type = :package_manager)
      return nil unless version_manager.deprecated?

      mode = NoticeMode::WARN
      supported_versions_description = generate_supported_versions_description(
        version_manager.supported_versions,
        version_manager.support_later_versions?,
        version_manager_type
      )
      notice_type = "#{version_manager.name}_deprecated_warn"
      title = version_manager_type == :language ? "Language deprecation notice" : "Package manager deprecation notice"
      description = "Dependabot will stop supporting `#{version_manager.name} v#{version_manager.version}`!"

      ## Add the supported versions to the description
      description += "\n\n#{supported_versions_description}\n" unless supported_versions_description.empty?

      Notice.new(
        mode: mode,
        type: notice_type,
        package_manager_name: version_manager.name,
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
      markdown += ">\n\n"
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
