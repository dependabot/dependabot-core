# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/shared/shared_file_updater"

module Dependabot
  module Docker
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      extend T::Sig

      YAML_REGEXP = /^[^\.].*\.ya?ml$/i
      DOCKER_REGEXP = /(docker|container)file/i
      FROM_REGEX = /FROM(\s+--platform\=\S+)?/i

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [DOCKER_REGEXP, YAML_REGEXP]
      end

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
    end
  end
end

Dependabot::FileUpdaters.register("docker", Dependabot::Docker::FileUpdater)
