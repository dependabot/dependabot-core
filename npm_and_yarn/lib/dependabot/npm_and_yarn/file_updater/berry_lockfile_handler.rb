# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "dependabot/npm_and_yarn/file_updater"

# Handles yarn berry lockfile manipulation — parsing descriptors, finding
# entries, and rewriting keys from exact versions back to ranges. This is
# the berry equivalent of yarn classic's replace-lockfile-declaration.ts.
module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      class BerryLockfileHandler
        extend T::Sig

        # Parses a yarn berry lockfile (YAML format). Returns nil if unparseable.
        sig { params(lockfile_path: String).returns(T.nilable(T::Hash[String, T.untyped])) }
        def self.parse(lockfile_path)
          return unless File.exist?(lockfile_path)

          parsed = YAML.safe_load_file(lockfile_path)
          parsed.is_a?(Hash) ? parsed : nil
        end

        # Checks if the parsed lockfile has the target version for a dependency.
        sig { params(parsed: T::Hash[String, T.untyped], dep_name: String, version: String).returns(T::Boolean) }
        def self.version_matches?(parsed, dep_name, version)
          parsed.any? do |key, value|
            next false unless value.is_a?(Hash)

            key.to_s.split(", ").any? { |part| split_descriptor(part)[0] == dep_name } &&
              value["version"] == version
          end
        end

        # Rewrites a lockfile descriptor key from exact version to range.
        # Example: "axios@npm:1.15.2" → "axios@npm:^1.15.2"
        # The resolved version, checksum, and dependencies remain unchanged.
        sig do
          params(
            lockfile_path: String,
            dep_name: String,
            version: String,
            requirement: String
          ).void
        end
        def self.replace_declaration(lockfile_path, dep_name, version, requirement)
          return unless File.exist?(lockfile_path)

          content = File.read(lockfile_path)
          parsed = parse(lockfile_path)
          return unless parsed

          exact_key = find_exact_key(parsed, dep_name, version)
          return unless exact_key

          protocol = extract_protocol(exact_key, dep_name)
          new_key = "#{dep_name}@#{protocol}#{requirement}"

          escaped = Regexp.escape(exact_key)
          File.write(lockfile_path, content.gsub(/^"#{escaped}":/m, "\"#{new_key}\":"))
        end

        # Finds the lockfile key containing the given dep name with exact version.
        # Handles composite keys (e.g., "a@npm:1.0, a@npm:^1.0").
        sig { params(parsed: T::Hash[String, T.untyped], dep_name: String, version: String).returns(T.nilable(String)) }
        def self.find_exact_key(parsed, dep_name, version)
          parsed.keys.find do |key|
            next false unless key.is_a?(String)

            key.split(", ").any? do |part|
              name, desc = split_descriptor(part)
              name == dep_name && (desc&.end_with?(version) || false)
            end
          end
        end

        # Splits a yarn berry descriptor into [package_name, version/range].
        # Handles scoped packages like @scope/pkg@npm:^1.0.0.
        sig { params(descriptor: String).returns([String, T.nilable(String)]) }
        def self.split_descriptor(descriptor)
          if descriptor.start_with?("@")
            at_index = descriptor.index("@", 1)
            return [descriptor, nil] unless at_index

            [T.must(descriptor[0...at_index]), descriptor[(at_index + 1)..]]
          else
            parts = descriptor.split("@", 2)
            [T.must(parts[0]), parts[1]]
          end
        end

        # Extracts the protocol prefix (e.g., "npm:") from a descriptor.
        sig { params(key: String, dep_name: String).returns(String) }
        def self.extract_protocol(key, dep_name)
          part = key.split(", ").find { |p| split_descriptor(p)[0] == dep_name }
          return "" unless part

          _, descriptor = split_descriptor(part)
          match = descriptor&.match(/^([a-z]+:)/)
          match ? T.must(match[1]) : ""
        end
      end
    end
  end
end
