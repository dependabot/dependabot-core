# frozen_string_literal: true

module Bump
  class BumpError < StandardError; end

  class VersionConflict < BumpError; end
  class DependencyFileNotEvaluatable < BumpError; end
  class DependencyFileNotResolvable < BumpError; end

  class DependencyFileNotFound < BumpError
    attr_reader :file_path

    def initialize(file_path, msg = nil)
      @file_path = file_path
      super(msg)
    end

    def file_name
      file_path.split("/").last
    end

    def directory
      # Directory should always start with a `/`
      file_path.split("/")[0..-2].join("/").sub(%r{^/*}, "/")
    end
  end

  class GitCommandError < BumpError
    attr_reader :command

    def initialize(command, msg = nil)
      @command = command
      super(msg)
    end
  end

  class PathBasedDependencies < BumpError
    attr_reader :dependencies

    def initialize(*dependencies)
      @dependencies = dependencies.flatten
      msg = "Path based dependencies are not supported. "\
            "Path based dependencies found: #{dependencies.join(', ')}"
      super(msg)
    end
  end
end
