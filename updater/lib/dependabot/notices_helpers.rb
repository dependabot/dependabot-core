# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/notices"
require "dependabot/ecosystem"
require "debug"

# This module extracts helpers for notice generations that can be used
# for showing notices in logs, pr messages and alert ui page.
module Dependabot
  module NoticesHelpers
    extend T::Sig
    extend T::Helpers

    abstract!

    # Add a deprecation notice to the notice list if the version manager is deprecated
    # if the version manager is deprecated.
    #  notices << deprecation_notices if deprecation_notices
    sig do
      params(
        notices: T::Array[Dependabot::Notice],
        version_manager: T.nilable(Ecosystem::VersionManager),
        version_manager_type: Symbol
      )
        .void
    end
    def add_deprecation_notice(notices:, version_manager:, version_manager_type: :package_manager)
      # Create a deprecation notice if the version manager is deprecated
      deprecation_notice = create_deprecation_notice(version_manager, version_manager_type)

      return unless deprecation_notice

      log_notice(deprecation_notice)

      notices << deprecation_notice
    end

    sig { params(notice: Dependabot::Notice).void }
    def log_notice(notice)
      logger = Dependabot.logger
      # Log each non-empty line of the deprecation notice description
      notice.description.each_line do |line|
        line = line.strip
        next if line.empty?

        case notice.mode
        when Dependabot::Notice::NoticeMode::INFO
          logger.info(line)
        when Dependabot::Notice::NoticeMode::WARN
          logger.warn(line)
        when Dependabot::Notice::NoticeMode::ERROR
          logger.error(line)
        else
          logger.info(line)
        end
      end
    end

    private

    sig do
      params(version_manager: T.nilable(Ecosystem::VersionManager),
             version_manager_type: Symbol).returns(T.nilable(Dependabot::Notice))
    end
    def create_deprecation_notice(version_manager, version_manager_type)
      return unless version_manager

      return unless version_manager.is_a?(Ecosystem::VersionManager)

      Notice.generate_deprecation_notice(version_manager, version_manager_type)
    end
  end
end
