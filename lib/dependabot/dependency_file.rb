# frozen_string_literal: true

module Dependabot
  class DependencyFile
    attr_accessor :name, :content, :directory, :type

    def initialize(name:, content:, directory: "/", type: "file")
      @name = name
      @content = content
      @directory = clean_directory(directory)
      @type = type
    end

    def to_h
      {
        "name" => name,
        "content" => content,
        "directory" => directory,
        "type" => type
      }
    end

    def path
      File.join(directory, name)
    end

    private

    def clean_directory(directory)
      # Directory should always start with a `/`
      directory.sub(%r{^/*}, "/")
    end
  end
end
