# frozen_string_literal: true

require "pathname"

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
      Pathname.new(File.join(directory, name)).cleanpath.to_path
    end

    def ==(other)
      other.instance_of?(self.class) && to_h == other.to_h
    end

    private

    def clean_directory(directory)
      # Directory should always start with a `/`
      directory.sub(%r{^/*}, "/")
    end
  end
end
