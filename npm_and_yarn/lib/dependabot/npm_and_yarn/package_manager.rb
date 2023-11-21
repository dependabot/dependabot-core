# typed: true
# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    class PackageManager
      def initialize(package_json, lockfiles:)
        @package_json = package_json
        @lockfiles = lockfiles
      end

      def version(name)
        requested_version(name) || guessed_version(name)
      end

      private

      def requested_version(name)
        version = @package_json.fetch("packageManager", nil)
        return unless version

        version_match = version.match(/#{name}@(?<version>\d+.\d+.\d+)/)
        version_match&.named_captures&.fetch("version", nil)
      end

      def guessed_version(name)
        send(:"guess_#{name}_version", @lockfiles[name.to_sym])
      end

      def guess_yarn_version(yarn_lock)
        return unless yarn_lock

        Helpers.yarn_version_numeric(yarn_lock)
      end

      def guess_pnpm_version(pnpm_lock)
        return unless pnpm_lock

        Helpers.pnpm_version_numeric(pnpm_lock)
      end
    end
  end
end
