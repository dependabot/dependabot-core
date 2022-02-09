# frozen_string_literal: true

require 'cocoapods-core'

module Dependabot
  module CocoaPods
    class Version < Pod::Version
      def initialize(version)
        @version_string = version.to_s
        super
      end

      def to_s
        @version_string
      end

      def self.correct?(version)
        super(Pod::Version.new(version))
      end
    end
  end
end

Dependabot::Utils
  .register_version_class('cocoapods', Dependabot::CocoaPods::Version)
