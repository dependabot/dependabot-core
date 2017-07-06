# frozen_string_literal: true

module Dependabot
  class DependabotError < StandardError; end

  class VersionConflict < DependabotError; end
  class DependencyFileNotEvaluatable < DependabotError; end
  class DependencyFileNotResolvable < DependabotError; end

  class DependencyFileNotFound < DependabotError
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

  class GitCommandError < DependabotError
    attr_reader :command

    def initialize(command, msg = nil)
      @command = command
      super(msg)
    end
  end

  class PathBasedDependencies < DependabotError
    attr_reader :dependencies

    def initialize(*dependencies)
      @dependencies = dependencies.flatten
      msg = "The following path based dependencies could not be retrieved: "\
            "#{dependencies.join(', ')}"
      super(msg)
    end
  end
end
