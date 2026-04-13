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
        url_match = FLAKE_URL_PATTERN.match(url_str)
        return unless url_match

        InputUrl.new(
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
        match = url_assignment.match(content)
        return url_match_hash(match) if match

        # Pattern 3: NAME = { ... url = "URL"; ... }
        # Use a non-greedy match to find the url inside the attribute set
        attr_set = /#{bounded_name}\s*=\s*\{[^}]*?\burl\s*=\s*"(?<url>[^"]+)"/m
        match = attr_set.match(content)
        return url_match_hash(match) if match

        nil
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
        base = "#{input_url.scheme}:#{input_url.owner}/#{input_url.repo}/#{new_ref}"
        input_url.query ? "#{base}?#{input_url.query}" : base
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
