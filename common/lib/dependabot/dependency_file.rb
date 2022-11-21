# frozen_string_literal: true

require "pathname"

module Dependabot
  class DependencyFile
    attr_accessor :name, :content, :directory, :type, :support_file,
                  :symlink_target, :content_encoding, :operation, :mode

    class ContentEncoding
      UTF_8 = "utf-8"
      BASE64 = "base64"
    end

    class Operation
      UPDATE = "update"
      CREATE = "create"
      DELETE = "delete"
    end

    def initialize(name:, content:, directory: "/", type: "file",
                   support_file: false, symlink_target: nil,
                   content_encoding: ContentEncoding::UTF_8, deleted: false,
                   operation: Operation::UPDATE, mode: nil)
      @name = name
      @content = content
      @directory = clean_directory(directory)
      @symlink_target = symlink_target
      @support_file = support_file
      @content_encoding = content_encoding
      @operation = operation

      # Make deleted override the operation. Deleted is kept when operation
      # was introduced to keep compatibility with downstream dependants.
      @operation = Operation::DELETE if deleted

      # Type is used *very* sparingly. It lets the git_modules updater know that
      # a "file" is actually a submodule, and lets our Go updaters know which
      # file represents the main.go.
      # New use cases should be avoided if at all possible (and use the
      # support_file flag instead)
      @type = type

      begin
        @mode = File.stat((symlink_target || path).sub(%r{^/}, "")).mode.to_s(8)
      rescue StandardError
        @mode = mode
      end

      return unless (type == "symlink") ^ symlink_target

      raise "Symlinks must specify a target!" unless symlink_target
      raise "Only symlinked files must specify a target!" if symlink_target
    end

    def to_h
      details = {
        "name" => name,
        "content" => content,
        "directory" => directory,
        "type" => type,
        "support_file" => support_file,
        "content_encoding" => content_encoding,
        "deleted" => deleted,
        "operation" => operation,
        "mode" => mode
      }

      details["symlink_target"] = symlink_target if symlink_target
      details
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

    def deleted
      @operation == Operation::DELETE
    end

    def deleted=(deleted)
      @operation = deleted ? Operation::DELETE : Operation::UPDATE
    end

    def deleted?
      deleted
    end

    def binary?
      content_encoding == ContentEncoding::BASE64
    end

    def decoded_content
      return Base64.decode64(content) if binary?

      content
    end

    private

    def clean_directory(directory)
      # Directory should always start with a `/`
      directory.sub(%r{^/*}, "/")
    end
  end
end
