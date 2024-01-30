# typed: strong
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"

module Dependabot
  class DependencyFile
    extend T::Sig

    sig { returns(String) }
    attr_accessor :name

    sig { returns(T.nilable(String)) }
    attr_accessor :content

    # This is the directory of the job source, not the directory of the file itself.
    # The name actually contains the relative path from the job directory.
    sig { returns(String) }
    attr_accessor :directory

    sig { returns(String) }
    attr_accessor :type

    sig { returns(T::Boolean) }
    attr_accessor :support_file

    sig { returns(T::Boolean) }
    attr_accessor :vendored_file

    sig { returns(T.nilable(String)) }
    attr_accessor :symlink_target

    sig { returns(String) }
    attr_accessor :content_encoding

    sig { returns(String) }
    attr_accessor :operation

    sig { returns(T.nilable(String)) }
    attr_accessor :mode

    class ContentEncoding
      UTF_8 = "utf-8"
      BASE64 = "base64"
    end

    class Operation
      UPDATE = "update"
      CREATE = "create"
      DELETE = "delete"
    end

    class Mode
      FILE = "100644"
      SUBMODULE = "160000"
    end

    sig do
      params(
        name: String,
        content: T.nilable(String),
        directory: String,
        type: String,
        support_file: T::Boolean,
        vendored_file: T::Boolean,
        symlink_target: T.nilable(String),
        content_encoding: String,
        deleted: T::Boolean,
        operation: String,
        mode: T.nilable(String)
      )
        .void
    end
    def initialize(name:, content:, directory: "/", type: "file",
                   support_file: false, vendored_file: false, symlink_target: nil,
                   content_encoding: ContentEncoding::UTF_8, deleted: false,
                   operation: Operation::UPDATE, mode: nil)
      @name = name
      @content = content
      @directory = T.let(clean_directory(directory), String)
      @symlink_target = symlink_target
      @support_file = support_file
      @vendored_file = vendored_file
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
        @mode = T.let(File.stat(realpath).mode.to_s(8), T.nilable(String))
      rescue StandardError
        @mode = mode
      end

      return unless (type == "symlink") ^ symlink_target

      raise "Symlinks must specify a target!" unless symlink_target
      raise "Only symlinked files must specify a target!" if symlink_target
    end

    sig { returns(T::Hash[String, T.untyped]) }
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

    sig { returns(String) }
    def path
      Pathname.new(File.join(directory, name)).cleanpath.to_path
    end

    sig { returns(String) }
    def realpath
      (symlink_target || path).sub(%r{^/}, "")
    end

    sig { params(other: BasicObject).returns(T::Boolean) }
    def ==(other)
      case other
      when DependencyFile
        my_hash = to_h.reject { |k| k == "support_file" }
        their_hash = other.to_h.reject { |k| k == "support_file" }
        my_hash == their_hash
      else
        false
      end
    end

    sig { returns(Integer) }
    def hash
      to_h.hash
    end

    sig { params(other: BasicObject).returns(T::Boolean) }
    def eql?(other)
      self == other
    end

    sig { returns(T::Boolean) }
    def support_file?
      @support_file
    end

    sig { returns(T::Boolean) }
    def vendored_file?
      @vendored_file
    end

    sig { returns(T::Boolean) }
    def deleted
      @operation == Operation::DELETE
    end

    sig { params(deleted: T::Boolean).void }
    def deleted=(deleted)
      @operation = deleted ? Operation::DELETE : Operation::UPDATE
    end

    sig { returns(T::Boolean) }
    def deleted?
      deleted
    end

    sig { returns(T::Boolean) }
    def binary?
      content_encoding == ContentEncoding::BASE64
    end

    sig { returns(String) }
    def decoded_content
      return Base64.decode64(T.must(content)) if binary?

      T.must(content)
    end

    private

    sig { params(directory: String).returns(String) }
    def clean_directory(directory)
      # Directory should always start with a `/`
      directory.sub(%r{^/*}, "/")
    end
  end
end
