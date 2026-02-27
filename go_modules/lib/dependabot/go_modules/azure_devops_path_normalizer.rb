# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "uri"

module Dependabot
  module GoModules
    module AzureDevopsPathNormalizer
      extend T::Sig

      sig { params(name: String).returns(String) }
      def self.normalize(name)
        return name unless name.start_with?("dev.azure.com/")
        return name if name.include?("/_git/")

        uri = URI.parse("https://#{name}")
        path = uri.path || ""
        segments = path.delete_prefix("/").split("/")
        return name if segments.length < 3

        normalized_segments = T.let([], T::Array[String])
        normalized_segments.concat(segments[0, 2] || [])
        normalized_segments << "_git"
        normalized_segments.concat(segments[2..] || [])

        uri.path = "/#{normalized_segments.join('/')}"
        uri.to_s.delete_prefix("https://")
      rescue URI::InvalidURIError
        name
      end
    end
  end
end
