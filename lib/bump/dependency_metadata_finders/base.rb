# frozen_string_literal: true
require "gems"

module Bump
  module DependencyMetadataFinders
    class Base
      GITHUB_REGEX = %r{github\.com/(?<repo>[^/]+/(?:(?!\.git)[^/])+)[\./]?}

      attr_reader :dependency

      def initialize(dependency:)
        @dependency = dependency
      end

      def github_repo
        return @github_repo if @github_repo_lookup_attempted
        look_up_github_repo
      end

      private

      def look_up_github_repo
        raise NotImplementedError
      end
    end
  end
end
