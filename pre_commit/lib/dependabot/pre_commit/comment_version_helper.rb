# typed: strict
# frozen_string_literal: true

module Dependabot
  module PreCommit
    module CommentVersionHelper
      # Matches a version string in a comment, with optional "v" prefix.
      # Examples: "v1", "v2.3.2", "7.3.0", "1.43.5"
      COMMENT_VERSION_PATTERN = T.let(/v?\d+(?:\.\d+)*/, Regexp)

      # Matches a version string preceded by a "frozen:" label or "#" prefix.
      # Captures the version string (with optional "v" prefix) in group 1.
      # Examples: "# frozen: v2.3.2" → "v2.3.2", "# v4.4.0" → "v4.4.0"
      FROZEN_COMMENT_REF_PATTERN = T.let(/(?:frozen:\s*|#\s*)(#{COMMENT_VERSION_PATTERN})/, Regexp)
    end
  end
end
