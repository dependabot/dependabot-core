# frozen_string_literal: true

module Dependabot
  module Utils
    module CocoaPods
      class Version < Gem::Version
        def initialize(version)
          @version_string = version.to_s
          super
        end

        def to_s
          @version_string
        end
      end
    end
  end
end
