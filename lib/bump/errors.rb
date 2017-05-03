# frozen_string_literal: true

module Bump
  class BumpError < StandardError; end

  class VersionConflict < BumpError; end
  class DependencyFileNotEvaluatable < BumpError; end

  class DependencyFileNotFound < BumpError
    attr_reader :file_name

    def initialize(file_name, msg = nil)
      @file_name = file_name
      super(msg)
    end
  end

  class GitCommandError < BumpError
    attr_reader :command

    def initialize(command, msg = nil)
      @command = command
      super(msg)
    end
  end
end
