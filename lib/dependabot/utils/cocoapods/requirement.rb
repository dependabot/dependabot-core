# frozen_string_literal: true

require "cocoapods-core"

module Dependabot
  module Utils
    module CocoaPods
      class Requirement < Pod::Requirement
        def self.parse(obj)
          Pod::Requirement.new(obj.to_s)
        end

      end
    end
  end
end
