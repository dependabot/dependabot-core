# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/registry_client"

module Dependabot
  module Nimble
    # The Nimble package index: which git repository a package name stands for.
    #
    # `nimble install foo` looks `foo` up in https://github.com/nim-lang/packages, published as one
    # JSON list. An entry has a `name`, a `url` and a `method` (`git` or `hg`), or is an `alias`
    # for another name. Package names ignore case and underscores.
    class PackageIndex
      extend T::Sig

      # Where `nimble` itself reads the index from, and the file it is published from.
      URLS = [
        "https://nim-lang.org/nimble/packages.json",
        "https://raw.githubusercontent.com/nim-lang/packages/master/packages.json"
      ].freeze
      MAX_ALIAS_DEPTH = 5

      Entry = T.type_alias { T::Hash[String, Object] }

      sig { params(urls: T::Array[String]).void }
      def initialize(urls: URLS)
        @urls = urls
        @entries = T.let(nil, T.nilable(T::Hash[String, Entry]))
      end

      # The https URL of the git repository of a package, or nil when the index does not know the
      # package or hosts it with something other than git.
      sig { params(name: String).returns(T.nilable(String)) }
      def repository_url(name)
        entry = resolve(name)
        return unless entry && entry["method"] == "git"

        normalize(entry["url"].to_s)
      end

      private

      sig { params(name: String, depth: Integer).returns(T.nilable(Entry)) }
      def resolve(name, depth = 0)
        entry = entries[key(name)]
        return unless entry
        return entry unless entry["alias"]
        return if depth >= MAX_ALIAS_DEPTH

        resolve(entry["alias"].to_s, depth + 1)
      end

      sig { returns(T::Hash[String, Entry]) }
      def entries
        @entries ||= T.let(load_entries, T.nilable(T::Hash[String, Entry]))
      end

      # The first address that answers with a list of packages decides.
      sig { returns(T::Hash[String, Entry]) }
      def load_entries
        @urls.each do |url|
          list = fetch_list(url)
          return list.to_h { |entry| [key(entry["name"].to_s), entry] } if list
        end
        {}
      end

      # The list published at `url`, or nil when it cannot be fetched or read.
      sig { params(url: String).returns(T.nilable(T::Array[Entry])) }
      def fetch_list(url)
        response = Dependabot::RegistryClient.get(url: url)
        return unless response.status == 200

        list = JSON.parse(response.body)
        list.is_a?(Array) ? list : nil
      rescue JSON::ParserError, Excon::Error
        nil
      end

      sig { params(name: String).returns(String) }
      def key(name)
        name.downcase.delete("_")
      end

      sig { params(url: T.nilable(String)).returns(T.nilable(String)) }
      def normalize(url)
        return if url.nil? || url.empty?

        url.sub(%r{\Agit://}, "https://").delete_suffix(".git").chomp("/")
      end
    end
  end
end
