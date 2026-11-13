# typed: strict
# frozen_string_literal: true

require "uri"
require "sorbet-runtime"

require "dependabot/nix/file_updater"

module Dependabot
  module Nix
    class FileUpdater < Dependabot::FileUpdaters::Base
      class FlakeRefBuilder
        extend T::Sig

        ARCHIVE_TYPES = %w(github gitlab sourcehut).freeze
        ARCHIVE_PATH_KEYS = %w(type owner repo ref rev).freeze
        GIT_URL_KEYS = %w(type url rev).freeze
        LOCKED_ONLY_KEYS = %w(lastModified narHash revCount).freeze
        SCP_STYLE_URL = /\A(?<user>[^@]+)@(?<host>[^:]+):(?<path>.+)\z/

        sig { params(source: T::Hash[String, Object], revision: String).void }
        def initialize(source:, revision:)
          @source = source
          @revision = revision
        end

        sig { returns(String) }
        def to_s
          source_type = required_string("type")

          if ARCHIVE_TYPES.include?(source_type)
            archive_reference(source_type)
          elsif source_type == "git"
            git_reference
          else
            raise ArgumentError, "Nix flake source type #{source_type.inspect} is not supported"
          end
        end

        private

        sig { returns(T::Hash[String, Object]) }
        attr_reader :source

        sig { returns(String) }
        attr_reader :revision

        sig { params(source_type: String).returns(String) }
        def archive_reference(source_type)
          owner = encode_path_segment(required_string("owner"))
          repo = encode_path_segment(required_string("repo"))
          base = "#{source_type}:#{owner}/#{repo}/#{encode_path_segment(revision)}"

          append_query(base, query_attributes(excluding: ARCHIVE_PATH_KEYS))
        end

        sig { returns(String) }
        def git_reference
          uri = URI.parse(normalized_git_url(required_string("url")))
          query = URI.decode_www_form(uri.query || "").to_h
          query.merge!(query_attributes(excluding: GIT_URL_KEYS))
          query["rev"] = revision
          uri.query = encoded_query(query)
          uri.to_s
        end

        sig { params(url: String).returns(String) }
        def normalized_git_url(url)
          return url if url.match?(/\Agit(?:\+[^:]+)?:/)

          if (match = SCP_STYLE_URL.match(url))
            return "git+ssh://#{match[:user]}@#{match[:host]}/#{match[:path]}"
          end

          uri = URI.parse(url)
          raise ArgumentError, "git source URL #{url.inspect} must include a scheme" unless uri.scheme

          "git+#{url}"
        end

        sig { params(excluding: T::Array[String]).returns(T::Hash[String, String]) }
        def query_attributes(excluding:)
          attributes = T.let({}, T::Hash[String, String])
          source.each do |key, value|
            next if excluding.include?(key) || LOCKED_ONLY_KEYS.include?(key) || value.nil?

            attributes[key] = query_value(value)
          end
          attributes
        end

        sig { params(base: String, query: T::Hash[String, String]).returns(String) }
        def append_query(base, query)
          return base if query.empty?

          "#{base}?#{encoded_query(query)}"
        end

        sig { params(query: T::Hash[String, String]).returns(String) }
        def encoded_query(query)
          URI.encode_www_form(query.sort)
        end

        sig { params(value: Object).returns(String) }
        def query_value(value)
          case value
          when true then "1"
          when false then "0"
          when String, Integer then value.to_s
          else
            raise ArgumentError, "Nix flake source attribute value #{value.inspect} is not supported"
          end
        end

        sig { params(value: String).returns(String) }
        def encode_path_segment(value)
          URI.encode_www_form_component(value)
             .gsub("+", "%20")
             .gsub("%7E", "~")
        end

        sig { params(key: String).returns(String) }
        def required_string(key)
          value = source[key]
          return value if value.is_a?(String) && !value.empty?

          raise ArgumentError, "Nix flake source is missing attribute #{key.inspect}"
        end
      end
    end
  end
end
