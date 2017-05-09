# frozen_string_literal: true
module Bump
  class DependencyFile
    attr_accessor :name, :content, :directory

    def initialize(name:, content:, directory: "/")
      @name = name
      @content = content
      @directory = clean_directory(directory)
    end

    def to_h
      { "name" => name, "content" => content, "directory" => directory }
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
