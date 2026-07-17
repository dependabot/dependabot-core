# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_updater"

module Dependabot
  module Gradle
    class FileUpdater
      module Wrapper
        # An order-preserving model of a `gradle-wrapper.properties` file.
        #
        # Java's `Properties.store` (used by Gradle's wrapper task) discards comments, blank
        # lines, custom keys and the original key ordering. To preserve everything the user
        # configured, we parse the original file into this document, mutate only the keys we
        # intend to change, and render it back verbatim.
        class PropertiesDocument
          extend T::Sig

          # A single physical line: either a raw line (comment/blank/unparsed) or a property.
          class Line < T::Struct
            prop :raw, String
            prop :indent, String, default: ""
            prop :key, T.nilable(String)
            prop :separator, T.nilable(String)
            prop :value, T.nilable(String)
          end

          # Properties files use `=`, `:` or whitespace as the key/value separator. Gradle always
          # writes `=`, but we parse all three so user-authored files are handled faithfully.
          KEY_VALUE_REGEX = T.let(/\A(\s*)([^\s:=]+)(\s*[:=]\s*|\s+)(.*)\z/, Regexp)
          COMMENT_REGEX = T.let(/\A\s*[#!]/, Regexp)

          sig { params(content: String).returns(PropertiesDocument) }
          def self.parse(content)
            lines = content.split("\n", -1).map { |line| parse_line(line) }
            new(lines)
          end

          sig { params(line: String).returns(Line) }
          def self.parse_line(line)
            return Line.new(raw: line) if line.strip.empty? || line.match?(COMMENT_REGEX)

            match = line.match(KEY_VALUE_REGEX)
            return Line.new(raw: line) unless match

            Line.new(
              raw: line,
              indent: match[1] || "",
              key: match[2],
              separator: match[3],
              value: match[4]
            )
          end

          sig { params(lines: T::Array[Line]).void }
          def initialize(lines)
            @lines = lines
          end

          sig { params(key: String).returns(T::Boolean) }
          def key?(key)
            @lines.any? { |line| line.key == key }
          end

          sig { params(key: String).returns(T.nilable(String)) }
          def value_for(key)
            @lines.find { |line| line.key == key }&.value
          end

          # Sets `key` to `value`, preserving the line's original position, indentation and separator
          # when the key already exists, otherwise appending a new `key=value` line at the end.
          sig { params(key: String, value: String).void }
          def upsert(key, value)
            existing = @lines.find { |line| line.key == key }
            if existing
              separator = existing.separator || "="
              existing.value = value
              existing.separator = separator
              existing.raw = "#{existing.indent}#{key}#{separator}#{value}"
              return
            end

            @lines << Line.new(raw: "#{key}=#{value}", key: key, separator: "=", value: value)
          end

          sig { returns(String) }
          def to_s
            @lines.map(&:raw).join("\n")
          end
        end
      end
    end
  end
end
