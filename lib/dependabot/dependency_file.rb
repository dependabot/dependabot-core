# frozen_string_literal: true

require "pathname"

module Dependabot
  class DependencyFile
    attr_accessor :name, :content, :directory, :type, :support_file

    def initialize(name:, content:, directory: "/", type: "file",
                   support_file: false)
      @name = name
      @content = content
      @directory = clean_directory(directory)
      @type = type
      @support_file = support_file
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

    def hash
      to_h.hash
    end

    def eql?(other)
      self.==(other)
    end

    private

    def clean_directory(directory)
      # Directory should always start with a `/`
      directory.sub(%r{^/*}, "/")
    end
  end
end
