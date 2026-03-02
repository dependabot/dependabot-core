# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module GoModules
    module AzureDevopsPathNormalizer
      extend T::Sig

      sig { params(name: String).returns(String) }
      def self.normalize(name)
        return name unless name.start_with?("dev.azure.com/")
        return name if name.include?("/_git/")

        segments = name.split("/")
        return name if segments.length < 4

        normalized_segments = T.let([], T::Array[String])
        normalized_segments.concat(segments[0, 3] || [])
        normalized_segments << "_git"
        normalized_segments.concat(segments[3..] || [])

        normalized_segments.join("/")
      end
    end
  end
end
