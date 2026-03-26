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

        segments = name.split("/")
        return name if segments.length < 4
        return name if segments[3] == "_git"

        normalized_segments = segments.dup
        normalized_segments.insert(3, "_git")
        normalized_segments[4] = normalized_segments.fetch(4).delete_suffix(".git")

        normalized_segments.join("/")
      end
    end
  end
end
