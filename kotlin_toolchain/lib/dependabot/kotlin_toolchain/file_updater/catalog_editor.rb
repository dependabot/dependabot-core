# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/errors"
require "dependabot/file_updaters/base"

module Dependabot
  module KotlinToolchain
    class FileUpdater < Dependabot::FileUpdaters::Base
      class CatalogEditor
        extend T::Sig

        TABLE_HEADER = /\A\s*\[(?!\[)\s*(?<key>[^\]]*?)\s*\]\s*(?:#.*)?\z/
        KEY_SEGMENT = /"(?<double>[^"]*)"|'(?<single>[^']*)'|(?<bare>[A-Za-z0-9_-]+)/
        ASSIGNMENT = /\A\s*(?<key>(?:#{KEY_SEGMENT})(?:\s*\.\s*(?:#{KEY_SEGMENT}))*)\s*=(?<value>.*)\z/m

        sig { params(content: String, filename: String).void }
        def initialize(content:, filename:)
          @content = content
          @filename = filename
        end

        sig { params(key: String, previous_version: String, new_version: String).returns(String) }
        def replace_version_key(key:, previous_version:, new_version:)
          replace(
            path: ["versions", *split_key(key)],
            description: "versions.#{key}",
            previous_version: previous_version,
            new_version: new_version
          )
        end

        sig { params(alias_name: String, previous_version: String, new_version: String).returns(String) }
        def replace_inline_version(alias_name:, previous_version:, new_version:)
          replace(
            path: ["libraries", *split_key(alias_name), "version"],
            description: "libraries.#{alias_name}",
            previous_version: previous_version,
            new_version: new_version,
            coordinate: true
          )
        end

        private

        sig { returns(String) }
        attr_reader :content

        sig { returns(String) }
        attr_reader :filename

        sig do
          params(
            path: T::Array[String],
            description: String,
            previous_version: String,
            new_version: String,
            coordinate: T::Boolean
          ).returns(String)
        end
        def replace(path:, description:, previous_version:, new_version:, coordinate: false)
          header = T.let([], T::Array[String])
          located = T.let(false, T::Boolean)

          lines = content.lines.map do |line|
            if (table = line.match(TABLE_HEADER))
              header = split_key(T.must(table[:key]))
              next line
            end

            updated = updated_line(line, header, path, previous_version, new_version, coordinate: coordinate)
            next line unless updated

            located = true
            updated
          end

          unless located
            raise Dependabot::DependencyFileNotResolvable,
                  "Unable to locate #{description} in #{filename}"
          end

          verify!(lines.join, path, new_version, coordinate: coordinate)
        end

        sig do
          params(
            line: String,
            header: T::Array[String],
            path: T::Array[String],
            previous_version: String,
            new_version: String,
            coordinate: T::Boolean
          ).returns(T.nilable(String))
        end
        def updated_line(line, header, path, previous_version, new_version, coordinate:)
          assignment = line.match(ASSIGNMENT)
          return unless assignment

          target = path.join(".")
          key = (header + split_key(T.must(assignment[:key]))).join(".")
          return unless key == target || target.start_with?("#{key}.")

          value = T.must(assignment[:value])
          updated = if key == target
                      replace_scalar(value, previous_version, new_version)
                    elsif coordinate && key == T.must(path[0...-1]).join(".") && value.strip.start_with?('"', "'")
                      replace_coordinate(value, previous_version, new_version)
                    else
                      replace_inline_entry(value, T.must(path.last), previous_version, new_version)
                    end
          return unless updated

          T.must(line[0, line.length - value.length]) + updated
        end

        sig { params(key: String).returns(T::Array[String]) }
        def split_key(key)
          key.to_enum(:scan, KEY_SEGMENT).filter_map do
            match = T.must(Regexp.last_match)
            match[:double] || match[:single] || match[:bare]
          end
        end

        sig { params(value: String, previous_version: String, new_version: String).returns(T.nilable(String)) }
        def replace_scalar(value, previous_version, new_version)
          substitute(value, /\A(\s*["'])#{Regexp.escape(previous_version)}(["'])/, previous_version, new_version)
        end

        sig { params(value: String, previous_version: String, new_version: String).returns(T.nilable(String)) }
        def replace_coordinate(value, previous_version, new_version)
          substitute(value, /(:)#{Regexp.escape(previous_version)}(["'])/, previous_version, new_version)
        end

        sig do
          params(
            value: String,
            key: String,
            previous_version: String,
            new_version: String
          ).returns(T.nilable(String))
        end
        def replace_inline_entry(value, key, previous_version, new_version)
          pattern = /(\b#{Regexp.escape(key)}\s*=\s*["'])#{Regexp.escape(previous_version)}(["'])/
          substitute(value, pattern, previous_version, new_version)
        end

        sig do
          params(
            value: String,
            pattern: Regexp,
            previous_version: String,
            new_version: String
          ).returns(T.nilable(String))
        end
        def substitute(value, pattern, previous_version, new_version)
          matches = value.scan(pattern).length
          if matches.zero?
            already_updated = pattern.source.sub(Regexp.escape(previous_version), Regexp.escape(new_version))
            return value if value.match?(Regexp.new(already_updated))

            return
          end
          return unless matches == 1

          value.sub(pattern) { "#{Regexp.last_match(1)}#{new_version}#{Regexp.last_match(2)}" }
        end

        sig do
          params(
            updated: String,
            path: T::Array[String],
            new_version: String,
            coordinate: T::Boolean
          ).returns(String)
        end
        def verify!(updated, path, new_version, coordinate:)
          parsed = TomlRB.parse(updated)
          value = dig(parsed, path)
          value = dig(parsed, T.must(path[0...-1])) if value.nil? && coordinate
          return updated if value == new_version
          return updated if coordinate && value.is_a?(String) && value.end_with?(":#{new_version}")

          raise Dependabot::DependencyFileNotResolvable,
                "Updating #{path.join('.')} in #{filename} did not produce #{new_version}"
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError => e
          raise Dependabot::DependencyFileNotParseable.new(filename, "#{filename}: #{e.message}")
        end

        # A quoted key such as "ktor.core" stays one segment in TOML while the
        # unquoted spelling nests, so every split of the path is tried.
        sig { params(table: Object, path: T::Array[String]).returns(Object) }
        def dig(table, path)
          return table if path.empty?
          return unless table.is_a?(Hash)

          path.length.downto(1) do |length|
            joined = T.must(path[0...length]).join(".")
            next unless table.key?(joined)

            found = dig(table[joined], T.must(path[length..]))
            return found unless found.nil?
          end
          nil
        end
      end
    end
  end
end
