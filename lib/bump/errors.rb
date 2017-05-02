# frozen_string_literal: true

module Bump
  class BumpError < StandardError; end

  class DependencyFileNotFound < BumpError
    attr_reader :file_name

    def initialize(file_name, msg = nil)
      @file_name = file_name
      super(msg)
    end
  end

  class GitCommandError < BumpError; end
end
