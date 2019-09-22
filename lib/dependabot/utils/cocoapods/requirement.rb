# frozen_string_literal: true

require "dependabot/utils/cocoapods/version"

module Dependabot
  module Utils
    module CocoaPods
      class Requirement < Gem::Requirement
        def self.parse(obj)
          new_version = Utils::CocoaPods::Version.new(obj.to_s)
          ["=", new_version] if obj.is_a?(Gem::Version)
        end
      end
    end
  end
end
