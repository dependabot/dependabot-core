# typed: true
# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    class PackageManager
      def initialize(package_json)
        @package_json = package_json
      end

      def requested_version(name)
        version = @package_json.fetch("packageManager", nil)
        return unless version

        version_match = version.match(/#{name}@(?<version>\d+.\d+.\d+)/)
        version_match&.named_captures&.fetch("version", nil)
      end
    end
  end
end
