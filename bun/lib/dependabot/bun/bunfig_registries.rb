# typed: strict
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/errors"
require "sorbet-runtime"
require "toml-rb"
require "uri"

module Dependabot
  module Bun
    module BunfigRegistries
      extend T::Sig

      sig { params(file: DependencyFile).returns(T.nilable(String)) }
      def self.npmrc_content(file)
        config = TomlRB.parse(T.must(file.content))
        install = config["install"]
        return unless install.is_a?(Hash)

        lines = T.let([], T::Array[String])
        registry = registry_url(install["registry"])
        scopes = install["scopes"]
        if scopes.is_a?(Hash)
          scopes.each do |scope, value|
            scope_name = scope.delete_prefix("@")
            url = registry_url(value)
            lines << "@#{scope_name}:registry=#{url}" if url && scope_name.match?(/\A[\w.-]+\z/)
          end
        end

        return unless registry || !lines.empty?

        ["registry=#{registry || 'https://registry.npmjs.org/'}", *lines, ""].join("\n")
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      sig { params(value: Object).returns(T.nilable(String)) }
      def self.registry_url(value)
        value = value["url"] if value.is_a?(Hash)
        return unless value.is_a?(String) && !value.match?(/[[:space:][:cntrl:]]/)

        uri = URI.parse(value)
        return unless uri.is_a?(URI::HTTP) && uri.host && !uri.query && !uri.fragment
        return value unless uri.userinfo

        uri.user = nil
        uri.password = nil
        uri.to_s
      rescue URI::InvalidURIError
        nil
      end
      private_class_method :registry_url
    end
  end
end
