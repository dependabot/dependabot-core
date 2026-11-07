# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Swift
    module XcodeFileHelpers
      extend T::Sig

      XCODEPROJ_SUFFIX = ".xcodeproj/"
      XCWORKSPACE_SUFFIX = ".xcworkspace/"
      PACKAGE_RESOLVED = "Package.resolved"

      sig { params(path: String).returns(T::Boolean) }
      def self.xcode_resolved_path?(path)
        return false unless path.end_with?(PACKAGE_RESOLVED)

        path.include?(XCODEPROJ_SUFFIX) || path.include?(XCWORKSPACE_SUFFIX)
      end

      sig { params(path: String).returns(T.nilable(String)) }
      def self.extract_xcode_scope_dir(path)
        # Find the first occurrence of .xcodeproj/ or .xcworkspace/
        xcodeproj_idx = path.index(XCODEPROJ_SUFFIX)
        xcworkspace_idx = path.index(XCWORKSPACE_SUFFIX)

        # Determine which match to use (earliest occurrence)
        match_idx = T.let(nil, T.nilable(Integer))
        suffix_len = T.let(0, Integer)

        if xcodeproj_idx && (xcworkspace_idx.nil? || xcodeproj_idx < xcworkspace_idx)
          match_idx = xcodeproj_idx
          suffix_len = XCODEPROJ_SUFFIX.length
        elsif xcworkspace_idx
          match_idx = xcworkspace_idx
          suffix_len = XCWORKSPACE_SUFFIX.length
        end

        return nil if match_idx.nil?

        # Return path up to and including the suffix (minus trailing /)
        path[0, match_idx + suffix_len - 1]
      end
    end
  end
end
