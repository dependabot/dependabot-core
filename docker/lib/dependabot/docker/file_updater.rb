# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/notices"
require "dependabot/shared/shared_file_updater"

module Dependabot
  module Docker
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      extend T::Sig

      YAML_REGEXP = /^[^\.].*\.ya?ml$/i
      FROM_REGEX = /FROM(\s+--platform\=\S+)?/i

      sig { override.returns(String) }
      def file_type
        "Dockerfile or Containerfile"
      end

      sig { override.returns(Regexp) }
      def yaml_file_pattern
        YAML_REGEXP
      end

      sig { override.returns(Regexp) }
      def container_image_regex
        %r{^#{FROM_REGEX}\s+(docker\.io/)?}o
      end

      sig { override.returns(T::Array[Dependabot::Notice]) }
      def notices
        return [] unless dependencies.any? { |dependency| dependency.metadata[:docker_cooldown_date_unavailable] }

        [Dependabot::Notice.new(
          mode: Dependabot::Notice::NoticeMode::WARN,
          type: "docker_cooldown_date_unavailable",
          package_manager_name: "docker",
          title: "Docker cooldown was not applied",
          description: "Cooldown was not applied because the registry did not provide a publication date.",
          show_in_pr: true,
          show_alert: false
        )]
      end
    end
  end
end

Dependabot::FileUpdaters.register("docker", Dependabot::Docker::FileUpdater)
