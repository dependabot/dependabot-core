# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/experiments"

module Dependabot
  module GoModules
    class GoWorkParser
      extend T::Sig

      STRING_ESCAPES = T.let(
        {
          "a" => "\a", "b" => "\b", "f" => "\f", "n" => "\n", "r" => "\r",
          "t" => "\t", "v" => "\v", "\\" => "\\", '"' => '"'
        }.freeze,
        T::Hash[String, String]
      )

      # Parses the `use` directives from go.work content.
      # Removes the `./` prefix and, with the experiment, decodes Go quoted strings.
      # `"."` is included when the root module is listed.
      # Result is deduped but not sorted, filtered, or re-prefixed.
      sig { params(content: String).returns(T::Array[String]) }
      def self.use_paths(content)
        return legacy_use_paths(content) unless Dependabot::Experiments.enabled?(:enable_go_work_version_sync)

        paths = T.let([], T::Array[String])
        in_use_block = T.let(false, T::Boolean)

        content.each_line do |line|
          line = line.strip
          if in_use_block
            if line.start_with?(")")
              in_use_block = false
              next
            end
          else
            directive = line.match(/\Ause[ \t]+(.+)\z/)
            next unless directive

            line = T.must(directive[1])
            if line.start_with?("(")
              in_use_block = true
              next
            end
          end

          path = normalize_path(line)
          paths << path unless path.empty?
        end

        paths.uniq
      end

      # Behaviour before the enable_go_work_version_sync experiment: only `use ./path` is recognised
      # on single lines and quotes are kept on block entries.
      sig { params(content: String).returns(T::Array[String]) }
      def self.legacy_use_paths(content)
        paths = T.let([], T::Array[String])

        content.scan(/^use\s+\(([^)]+)\)/m).each do |block_match|
          T.must(block_match[0]).each_line do |line|
            path = line.split("//").first&.strip || ""
            next if path.empty?

            paths << path.sub(%r{^\./}, "")
          end
        end

        content.scan(/^use\s+(?!\()(\.[^\s]*)/m).each do |match|
          paths << T.must(match[0]).sub(%r{^\./}, "")
        end

        paths.uniq
      end
      private_class_method :legacy_use_paths

      sig { params(raw_path: String).returns(String) }
      def self.normalize_path(raw_path)
        return "" if raw_path.empty? || raw_path.start_with?("//")

        path = if raw_path.start_with?('"')
                 unquote_path(raw_path)
               else
                 raw_path.split(%r{\s|//}, 2).first || ""
               end
        path.delete_prefix("./")
      end
      private_class_method :normalize_path

      sig { params(raw_path: String).returns(String) }
      def self.unquote_path(raw_path)
        match = raw_path.match(%r{\A"((?:\\.|[^"\\])*)"\s*(?://.*)?\z})
        raise Dependabot::DependencyFileNotParseable.new("go.work", "Invalid quoted workspace path") unless match

        # Octal and hexadecimal escapes encode bytes, which may together form a UTF-8 character.
        path = T.must(match[1]).b.gsub(/\\(?:[0-7]{3}|x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}|.)/) do |escape|
          decode_escape(escape).b
        end
        path.force_encoding(Encoding::UTF_8)
      end
      private_class_method :unquote_path

      sig { params(escape: String).returns(String) }
      def self.decode_escape(escape)
        case escape
        when /\A\\[0-7]{3}\z/
          T.must(escape[1..]).to_i(8).chr(Encoding::BINARY)
        when /\A\\x[0-9a-fA-F]{2}\z/
          T.must(escape[2..]).to_i(16).chr(Encoding::BINARY)
        when /\A\\(?:u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8})\z/
          codepoint = T.must(escape[2..]).to_i(16)
          raise RangeError if codepoint > 0x10ffff || (0xd800..0xdfff).cover?(codepoint)

          [codepoint].pack("U")
        else
          STRING_ESCAPES.fetch(T.must(escape[1..])) { raise RangeError }
        end
      rescue RangeError
        raise Dependabot::DependencyFileNotParseable.new("go.work", "Invalid Go string escape: #{escape}")
      end
      private_class_method :decode_escape
    end
  end
end
