# frozen_string_literal: true

require "dependabot/utils"

module DummyPackageManager
  class Version < Gem::Version
    def initialize(version)
      version = Version.remove_leading_v(version)
      super
    end

    def self.remove_leading_v(version)
      return version unless version.to_s.match?(/\Av([0-9])/)

      version.to_s.gsub(/\Av/, "")
    end

    def self.correct?(version)
      version = Version.remove_leading_v(version)
      super
    end
  end
end

Dependabot::Utils.
  register_version_class("dummy", DummyPackageManager::Version)
