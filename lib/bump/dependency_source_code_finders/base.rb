# frozen_string_literal: true
require "gems"

module DependencySourceCodeFinders
  class Base
    GITHUB_REGEX = %r{github\.com/(?<repo>[^/]+/(?:(?!\.git)[^/])+)[\./]?}

    attr_reader :dependency_name

    def initialize(dependency_name:)
      @dependency_name = dependency_name
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
