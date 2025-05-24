require "dependabot/version"

module Dependabot
  module Julia
    class Version < Dependabot::Version
      def self.correct?(version_string)
        return false if version_string.nil?
        
        version_string = version_string.gsub(/^v/, "") if version_string.is_a?(String)
        super(version_string)
      end

      def initialize(version)
        @version_string = version.to_s
        version = version.gsub(/^v/, "") if version.is_a?(String)
        super
      end
    end
  end
end
