# typed: strict
# frozen_string_literal: true

require "uri"
require "sorbet-runtime"

module Dependabot
  module Swift
    # Shared URL normalization utilities used by multiple parsers.
    # Produces a canonical dependency name from a git repository URL
    # by stripping the scheme, "www." prefix, and ".git" suffix.
    module UrlHelpers
      extend T::Sig

      sig { params(source: String).returns(String) }
      def self.normalize_name(source)
        uri = URI.parse(source.downcase)
        "#{uri.host}#{uri.path}".delete_prefix("www.").delete_suffix(".git")
      rescue URI::InvalidURIError
        source.downcase.delete_suffix(".git")
      end
    end
  end
end
