# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Swift
    module XcodeFileHelpers
      extend T::Sig

      XCODE_RESOLVED_FILE_REGEX = %r{(?:\.xcodeproj|\.xcworkspace)/.*Package\.resolved\z}
      XCODE_SCOPE_REGEX = %r{^(.*?\.(?:xcodeproj|xcworkspace))/}

      sig { params(path: String).returns(T::Boolean) }
      def self.xcode_resolved_path?(path)
        XCODE_RESOLVED_FILE_REGEX.match?(path)
      end

      sig { params(path: String).returns(T.nilable(String)) }
      def self.extract_xcode_scope_dir(path)
        path.match(XCODE_SCOPE_REGEX)&.captures&.first
      end
    end
  end
end
