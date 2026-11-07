# typed: strong
# frozen_string_literal: true

require "shellwords"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/shared_helpers"

module Dependabot
  # Reconciles the line endings of updated file content to the form git would
  # store in the index. Dependabot commits via provider APIs, which bypass git's
  # `.gitattributes` clean filter, so without this an update can reintroduce line
  # endings the repo doesn't expect (e.g. a CRLF gradlew.bat under
  # `*.bat text eol=crlf`), leaving the file permanently "modified".
  module GitAttributes
    extend T::Sig

    CRLF = "\r\n"
    LF = "\n"

    sig do
      params(
        updated_files: T::Array[Dependabot::DependencyFile],
        original_files: T::Array[Dependabot::DependencyFile],
        repo_contents_path: T.nilable(String)
      ).void
    end
    def self.reconcile_line_endings!(updated_files, original_files:, repo_contents_path:)
      return unless repo_contents_path && Dir.exist?(File.join(repo_contents_path, ".git"))

      candidates = updated_files.reject { |f| f.binary? || f.content.nil? }
      return if candidates.empty?

      attrs = attributes_for(candidates.map(&:realpath), repo_contents_path)
      originals = original_files.to_h { |f| [f.name, f] }

      candidates.each { |file| reconcile_file!(file, attrs[file.realpath] || {}, originals[file.name]) }
    end

    sig do
      params(
        file: Dependabot::DependencyFile,
        attrs: T::Hash[String, String],
        original: T.nilable(Dependabot::DependencyFile)
      ).void
    end
    def self.reconcile_file!(file, attrs, original)
      content = T.must(file.content)
      target = target_eol(attrs, content, original)
      file.content = convert(content, target) unless target.nil?
    end

    # Resolves the target index-form EOL: :lf, :crlf, or nil (leave untouched).
    sig do
      params(
        attrs: T::Hash[String, String],
        content: String,
        original: T.nilable(Dependabot::DependencyFile)
      ).returns(T.nilable(Symbol))
    end
    def self.target_eol(attrs, content, original)
      text = attrs["text"]

      # An explicit `text`, or a bare `eol=` rule (which implicitly sets
      # `text` when it was left unspecified), forces normalization: anything
      # git normalizes is stored LF in the index; eol=crlf only affects
      # checkout, never the committed blob.
      return :lf if text == "set"
      return :lf if text == "unspecified" && %w(lf crlf).include?(attrs["eol"].to_s)

      # Content git's heuristic classifies as binary is stored verbatim under
      # text=auto, and is too risky to rewrite under any fallback.
      return nil if binary_content?(content)

      # Deliberately more eager than git, which skips conversion for blobs
      # whose committed form still has CRLF (the "safer autocrlf" rule): the
      # update visibly renormalizes the file to what the attributes declare.
      return :lf if text == "auto"

      # -text or no governing attribute: git stores the bytes verbatim, so
      # match the original file's endings to avoid noisy diffs.
      original_eol(original)
    end

    # Mixed-ending originals have no convention to match and are left untouched.
    sig { params(original: T.nilable(Dependabot::DependencyFile)).returns(T.nilable(Symbol)) }
    def self.original_eol(original)
      content = original&.content
      return nil if content.nil? || content.empty?
      return :lf unless content.include?(CRLF)
      return :crlf unless content.gsub(CRLF, "").include?(LF)

      nil
    end

    # Mirrors git's convert_is_binary (convert.c): NUL bytes, lone CRs, or a
    # high ratio of non-printable characters mean the content is not text.
    # Streams byte-wise; materializing an array would cost ~8x the file size.
    sig { params(content: String).returns(T::Boolean) }
    def self.binary_content?(content)
      printable = 0
      nonprintable = 0
      prev = T.let(nil, T.nilable(Integer))

      content.each_byte do |byte|
        return true if prev == 0x0d && byte != 0x0a # lone CR

        case byte
        when 0x00 then return true
        when 0x0a, 0x0d then nil
        when 0x08, 0x09, 0x0c, 0x1b then printable += 1
        when 0x7f then nonprintable += 1
        else byte < 0x20 ? nonprintable += 1 : printable += 1
        end
        prev = byte
      end
      return true if prev == 0x0d # trailing lone CR

      # A trailing DOS EOF marker (^Z) doesn't count against the content.
      nonprintable -= 1 if prev == 0x1a

      (printable >> 7) < nonprintable
    end

    sig { params(content: String, target: Symbol).returns(String) }
    def self.convert(content, target)
      lf = content.gsub(CRLF, LF)
      target == :crlf ? lf.gsub(LF, CRLF) : lf
    end

    # Half of Linux's 128KiB cap on a single argv entry, which is what limits
    # the assembled shell command; vendored updates can carry thousands of paths.
    COMMAND_BYTE_BUDGET = 65_536

    # Resolves attributes in size-bounded `git check-attr` batches; returns
    # { realpath => { attr => value } }. The paths must stay on the command
    # line: `check-attr --stdin` silently reads nothing through the git shim
    # that fronts git in the updater images.
    sig do
      params(paths: T::Array[String], repo_contents_path: String)
        .returns(T::Hash[String, T::Hash[String, String]])
    end
    def self.attributes_for(paths, repo_contents_path)
      batches(paths.map { |p| Shellwords.escape(p) }).reduce({}) do |result, batch|
        output = SharedHelpers.run_shell_command(
          "git check-attr -z text eol -- #{batch.join(' ')}",
          cwd: repo_contents_path,
          stderr_to_stdout: false,
          allow_unsafe_shell_command: true
        ).to_s

        result.merge!(parse(output))
      end
    end

    # Groups the escaped paths so each command stays within COMMAND_BYTE_BUDGET.
    sig { params(escaped: T::Array[String]).returns(T::Array[T::Array[String]]) }
    def self.batches(escaped)
      result = T.let([[]], T::Array[T::Array[String]])
      bytes = 0

      escaped.each do |path|
        if bytes + path.bytesize + 1 > COMMAND_BYTE_BUDGET && !T.must(result.last).empty?
          result << []
          bytes = 0
        end
        T.must(result.last) << path
        bytes += path.bytesize + 1
      end

      result.reject(&:empty?)
    end

    # `-z` output is a flat stream of NUL-terminated <path> <attr> <value> triples.
    sig { params(output: String).returns(T::Hash[String, T::Hash[String, String]]) }
    def self.parse(output)
      result = T.let(Hash.new { |h, k| h[k] = {} }, T::Hash[String, T::Hash[String, String]])
      output.split("\x00").each_slice(3) do |path, attr, value|
        next if path.nil? || attr.nil? || value.nil?

        T.must(result[path])[attr] = value
      end
      result
    end
  end
end
