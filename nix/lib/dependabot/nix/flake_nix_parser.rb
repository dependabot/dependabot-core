# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Nix
    # Parses flake.nix content to locate input URL declarations and extract
    # their components (scheme, owner, repo, ref). Only handles the shorthand
    # URL schemes (github:, gitlab:, sourcehut:) since those are the ones
    # where the ref appears inline in the URL string.
    class FlakeNixParser
      extend T::Sig

      # Matches shorthand flake URLs: github:owner/repo/ref or github:owner/repo
      # Also handles gitlab: and sourcehut:~owner/repo/ref
      FLAKE_URL_PATTERN = %r{
        (?<scheme>github|gitlab|sourcehut):
        (?<owner>~?[a-zA-Z0-9_\-\.]+)/
        (?<repo>[a-zA-Z0-9_\-\.]+)
        (?:/(?<ref>[a-zA-Z0-9_\-\./]+))?
        (?:\?(?<query>[^"]*))?
      }x
      private_constant :FLAKE_URL_PATTERN

      # Matches indirect/registry shorthand URLs: nixpkgs/nixos-24.11
      # These have no scheme prefix (no ":") and resolve via the nix flake registry.
      INDIRECT_URL_PATTERN = %r{
        \A(?<id>[a-zA-Z0-9_\-]+)
        /(?<ref>[a-zA-Z0-9_\-\./]+)\z
      }x
      private_constant :INDIRECT_URL_PATTERN

      # Matches an input URL assignment tied to a specific input name.
      # Covers the common syntactic forms:
      #   inputs.NAME.url = "URL";
      #   NAME.url = "URL";
      #   NAME = { ... url = "URL"; ... };
      #
      # We build these dynamically per input name so that the name is anchored
      # in the regex.
      sig { params(content: String, input_name: String).returns(T.nilable(InputUrl)) }
      def self.find_input_url(content, input_name)
        new(content, input_name).find
      end

      sig { params(content: String, input_name: String, new_ref: String).returns(T.nilable(String)) }
      def self.update_input_ref(content, input_name, new_ref)
        new(content, input_name).update_ref(new_ref)
      end

      sig { params(content: String, input_name: String).void }
      def initialize(content, input_name)
        @content = content
        @input_name = input_name
      end

      sig { returns(T.nilable(InputUrl)) }
      def find
        match = find_url_match
        return unless match

        url_str = match[:url]

        # Try shorthand scheme first (github:, gitlab:, sourcehut:)
        url_match = FLAKE_URL_PATTERN.match(url_str)
        if url_match
          return InputUrl.new(
            full_url: url_str,
            scheme: T.must(url_match[:scheme]),
            owner: T.must(url_match[:owner]),
            repo: T.must(url_match[:repo]),
            ref: url_match[:ref],
            query: url_match[:query],
            match_start: match[:url_start],
            match_end: match[:url_end]
          )
        end

        # Try indirect/registry shorthand (e.g. nixpkgs/nixos-24.11)
        indirect_match = INDIRECT_URL_PATTERN.match(url_str)
        return unless indirect_match

        InputUrl.new(
          full_url: url_str,
          scheme: "indirect",
          owner: T.must(indirect_match[:id]),
          repo: "",
          ref: indirect_match[:ref],
          query: nil,
          match_start: match[:url_start],
          match_end: match[:url_end]
        )
      end

      sig { params(new_ref: String).returns(T.nilable(String)) }
      def update_ref(new_ref)
        input_url = find
        return unless input_url
        return unless input_url.ref # nothing to update if no ref

        old_url = input_url.full_url
        new_url = build_updated_url(input_url, new_ref)

        updated = @content.dup
        # Replace within the known match boundaries to avoid accidental matches elsewhere
        updated[input_url.match_start...input_url.match_end] =
          T.must(updated[input_url.match_start...input_url.match_end]).sub(old_url, new_url)
        updated
      end

      private

      sig { returns(String) }
      attr_reader :content

      sig { returns(String) }
      attr_reader :input_name

      # Returns a hash with :url, :url_start, :url_end if found, or nil.
      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def find_url_match
        escaped_name = Regexp.escape(input_name)
        # Nix identifiers can contain letters, digits, underscores, hyphens, and apostrophes.
        # Anchor the name so we don't match inside longer identifiers (e.g. "my-nixpkgs").
        bounded_name = "(?<![A-Za-z0-9_'\\-])#{escaped_name}(?![A-Za-z0-9_'\\-])"

        # Pattern 1: inputs.NAME.url = "URL";
        # Pattern 2: NAME.url = "URL";  (inside inputs block)
        url_assignment = /(?:inputs\.)?#{bounded_name}\.url\s*=\s*"(?<url>[^"]+)"/
        match = find_uncommented_match(url_assignment)
        return url_match_hash(match) if match

        # Pattern 3: NAME = { ... url = "URL"; ... }
        # Use a non-greedy match to find the url inside the attribute set
        attr_set = /#{bounded_name}\s*=\s*\{[^}]*?\burl\s*=\s*"(?<url>[^"]+)"/m
        match = find_uncommented_match(attr_set)
        return url_match_hash(match) if match

        nil
      end

      # Finds the first match that isn't inside a Nix comment (# or /* */).
      sig { params(pattern: Regexp).returns(T.nilable(MatchData)) }
      def find_uncommented_match(pattern)
        content.to_enum(:scan, pattern).each do
          match = T.must(Regexp.last_match)
          next if inside_comment?(match.begin(0))

          return match
        end
        nil
      end

      sig { params(pos: Integer).returns(T::Boolean) }
      def inside_comment?(pos)
        # Check for single-line comment: # at start of line before pos
        line_start = content.rindex("\n", pos)&.+(1) || 0
        line_before_pos = content[line_start...pos]
        return true if line_before_pos&.match?(/(?:^|[^&])#/)

        # Check for block comment: /* before pos without a closing */ between them
        last_open = content.rindex("/*", pos)
        return false unless last_open

        last_close = content.rindex("*/", pos)
        last_open > (last_close || -1)
      end

      sig { params(match: MatchData).returns(T::Hash[Symbol, T.untyped]) }
      def url_match_hash(match)
        url_capture_start = match.begin(:url)
        url_capture_end = match.end(:url)
        {
          url: match[:url],
          url_start: url_capture_start,
          url_end: url_capture_end
        }
      end

      sig { params(input_url: InputUrl, new_ref: String).returns(String) }
      def build_updated_url(input_url, new_ref)
        if input_url.scheme == "indirect"
          "#{input_url.owner}/#{new_ref}"
        else
          base = "#{input_url.scheme}:#{input_url.owner}/#{input_url.repo}/#{new_ref}"
          input_url.query ? "#{base}?#{input_url.query}" : base
        end
      end

      # Represents a parsed flake input URL from flake.nix
      class InputUrl < T::Struct
        const :full_url, String
        const :scheme, String
        const :owner, String
        const :repo, String
        const :ref, T.nilable(String)
        const :query, T.nilable(String)
        # Character positions of the URL string within the flake.nix content
        # (inside the quotes, not including the quotes themselves)
        const :match_start, Integer
        const :match_end, Integer
      end
    end
  end
end
