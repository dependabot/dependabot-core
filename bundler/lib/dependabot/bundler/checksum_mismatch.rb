# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "uri"
require "dependabot/errors"
require "dependabot/shared_helpers"

module Dependabot
  module Bundler
    # Bundler (2.5+) refuses to resolve when two sources report different
    # checksums for the same gem version, e.g. the lockfile CHECKSUMS section
    # and the registry's compact index. Because Bundler checks every gem it
    # fetches, one bad entry blocks updates to all dependencies in the lockfile.
    #
    # This turns that helper failure into a DependencyChecksumMismatch whose
    # message names the gem and both checksums. Bundler's own message is not
    # passed through: it suggests disabling checksum validation and can include
    # local file paths.
    module ChecksumMismatch
      extend T::Sig

      ERROR_CLASS = "Bundler::ChecksumMismatchError"
      HEADER = "Bundler found mismatched checksums."
      ENTRY_LINE = /\A  (?<lock_name>\S+ \([^)\s]+\)) (?<checksum>[A-Za-z0-9]+=\S+)\z/
      SOURCE_LINE = /\A    (?:from|and) (?<source>\S.*)\z/
      LOCKFILE_SOURCE_PREFIX = "the lockfile CHECKSUMS at "
      API_SOURCE_PREFIX = "the API at "
      GEM_SOURCE_PREFIX = "the gem at "
      BUNDLER_LOCK_NAME_PREFIX = "bundler ("

      GENERIC_MESSAGE =
        "Bundler found mismatched checksums for a gem in your lockfile, so Dependabot " \
        "can't update it. Check that the checksums in your lockfile match the gems " \
        "served by your registries."

      class ChecksumEntry < T::Struct
        const :lock_name, String
        const :checksum, String
        const :sources, T::Array[String]
      end

      class ParsedMismatch < T::Struct
        const :lock_name, String
        const :entries, T::Array[ChecksumEntry]
      end

      sig do
        params(error: Dependabot::SharedHelpers::HelperSubprocessFailed)
          .returns(T.nilable(Dependabot::DependencyChecksumMismatch))
      end
      def self.error_for(error)
        return nil unless error.error_class == ERROR_CLASS

        parsed = parse(error.message)
        return Dependabot::DependencyChecksumMismatch.new(GENERIC_MESSAGE) unless parsed

        # A mismatch on Bundler itself comes from the Bundler installed in the
        # runner, not from the user's files, so leave it as an unknown error.
        return nil if parsed.lock_name.start_with?(BUNDLER_LOCK_NAME_PREFIX)

        Dependabot::DependencyChecksumMismatch.new(
          build_message(parsed),
          dependency_name: parsed.lock_name
        )
      end

      # Expected shape (each side may list several sources joined by "and"):
      #
      #   Bundler found mismatched checksums. This is a potential security risk.
      #     rack (2.2.3) sha256=aaa...
      #       from the lockfile CHECKSUMS at Gemfile.lock:16:16
      #     rack (2.2.3) sha256=bbb...
      #       from the API at https://rubygems.org/
      sig { params(message: String).returns(T.nilable(ParsedMismatch)) }
      def self.parse(message)
        entries = parse_entries(mismatch_lines(message))
        return nil unless entries && entries.size == 2
        return nil unless entries.map(&:lock_name).uniq.size == 1
        return nil if entries.any? { |entry| entry.sources.empty? }

        ParsedMismatch.new(lock_name: T.must(entries.first).lock_name, entries: entries)
      end

      # The lines between the header and the first blank line. The advice that
      # follows differs between Bundler versions, so it isn't parsed.
      sig { params(message: String).returns(T.nilable(T::Array[String])) }
      def self.mismatch_lines(message)
        lines = message.lines.map(&:chomp)
        header_index = lines.index { |line| line.start_with?(HEADER) }
        return nil unless header_index

        lines.drop(header_index + 1).take_while { |line| !line.strip.empty? }
      end

      sig { params(lines: T.nilable(T::Array[String])).returns(T.nilable(T::Array[ChecksumEntry])) }
      def self.parse_entries(lines)
        return nil unless lines

        entries = T.let([], T::Array[ChecksumEntry])
        lines.each do |line|
          if (entry = ENTRY_LINE.match(line))
            entries << ChecksumEntry.new(
              lock_name: T.must(entry[:lock_name]),
              checksum: T.must(entry[:checksum]),
              sources: []
            )
          elsif (source = SOURCE_LINE.match(line)) && (last_entry = entries.last)
            last_entry.sources << T.must(source[:source])
          else
            return nil
          end
        end
        entries
      end

      sig { params(parsed: ParsedMismatch).returns(String) }
      def self.build_message(parsed)
        first, second = parsed.entries
        "Bundler found mismatched checksums for #{parsed.lock_name}: " \
          "#{describe(T.must(first))}, but #{describe(T.must(second))}. " \
          "#{resolution_advice(parsed)}"
      end

      sig { params(entry: ChecksumEntry).returns(String) }
      def self.describe(entry)
        "#{entry.checksum} from #{entry.sources.map { |source| describe_source(source) }.join(' and ')}"
      end

      sig { params(source: String).returns(String) }
      def self.describe_source(source)
        return describe_api_source(source) if source.start_with?(API_SOURCE_PREFIX)
        # Only show file names: full paths are locations inside the runner.
        if source.start_with?(LOCKFILE_SOURCE_PREFIX)
          return "#{LOCKFILE_SOURCE_PREFIX}#{File.basename(source.delete_prefix(LOCKFILE_SOURCE_PREFIX))}"
        end
        return "the gem file #{File.basename(source.delete_prefix(GEM_SOURCE_PREFIX))}" if
          source.start_with?(GEM_SOURCE_PREFIX)

        "another source"
      end

      # Only show the registry's scheme, host and port. Bundler removes user
      # info, but some registries (e.g. Gemfury) put a token in the path.
      sig { params(source: String).returns(String) }
      def self.describe_api_source(source)
        uri = URI.parse(source.delete_prefix(API_SOURCE_PREFIX))
        host = uri.host
        return "a registry" unless uri.scheme && host

        default_port = T.let(uri.default_port, T.nilable(Integer))
        port = uri.port == default_port ? "" : ":#{uri.port}"
        "#{API_SOURCE_PREFIX}#{uri.scheme}://#{host}#{port}"
      rescue URI::InvalidURIError
        "a registry"
      end

      sig { params(parsed: ParsedMismatch).returns(String) }
      def self.resolution_advice(parsed)
        from_lockfile = parsed.entries.any? do |entry|
          entry.sources.any? { |source| source.start_with?(LOCKFILE_SOURCE_PREFIX) }
        end

        if from_lockfile
          "Dependabot can't update this lockfile until they match. Check which copy of the " \
            "gem is correct. If the registry's copy is correct, remove the #{parsed.lock_name} " \
            "entry from the CHECKSUMS section of your lockfile (and any stale copy of the gem in " \
            "vendor/cache), then run `bundle lock`. " \
            "Otherwise, republish the gem so the registry serves the expected file."
        else
          "Dependabot can't update this lockfile until they match. Check that the gem " \
            "served by your registry is the one you expect."
        end
      end

      private_class_method :parse,
                           :mismatch_lines,
                           :parse_entries,
                           :build_message,
                           :describe,
                           :describe_source,
                           :describe_api_source,
                           :resolution_advice
    end
  end
end
