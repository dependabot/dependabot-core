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
      @support_file = support_file

      # Type is used *very* sparingly. It lets the git_modules updater know that
      # a "file" is actually a submodule, and lets our Go updaters know which
      # file represents the main.go.
      # New use cases should be avoided if at all possible (and use the
      # support_file flag instead)
      @type = type
    end

    def to_h
      {
        "name" => name,
        "content" => content,
        "directory" => directory,
        "type" => type,
        "support_file" => support_file
      }
    end

    def path
      Pathname.new(File.join(directory, name)).cleanpath.to_path
    end

    def ==(other)
      return false unless other.instance_of?(self.class)

      my_hash = to_h.reject { |k| k == "support_file" }
      their_hash = other.to_h.reject { |k| k == "support_file" }
      my_hash == their_hash
    end

    def hash
      to_h.hash
    end

    def eql?(other)
      self.==(other)
    end

    def support_file?
      @support_file
    end

    private

    def clean_directory(directory)
      # Directory should always start with a `/`
      directory.sub(%r{^/*}, "/")
    end
  end
end
