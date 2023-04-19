# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    class PackageManager
      def initialize(package_json)
        @package_json = package_json
      end

      def locked_version(name)
        locked = @package_json.fetch("packageManager", nil)
        return unless locked

        version_match = locked.match(/#{name}@(?<version>\d+.\d+.\d+)/)
        version_match&.named_captures&.fetch("version", nil)
      end
    end
  end
end
