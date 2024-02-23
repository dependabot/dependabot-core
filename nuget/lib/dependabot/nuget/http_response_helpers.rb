# typed: true
# frozen_string_literal: true

module Dependabot
  module Nuget
    module HttpResponseHelpers
      def self.remove_wrapping_zero_width_chars(string)
        string.force_encoding("UTF-8").encode
              .gsub(/\A[\u200B-\u200D\uFEFF]/, "")
              .gsub(/[\u200B-\u200D\uFEFF]\Z/, "")
      end
    end
  end
end
