# typed: strong
# frozen_string_literal: true

require "time"
require "sorbet-runtime"
require "dependabot/package/package_release"
require "dependabot/pub/json_value_parser"
require "dependabot/pub/version"

module Dependabot
  module Pub
    module Package
      class RegistryPackage
        extend T::Sig

        sig { params(content: String).returns(RegistryPackage) }
        def self.from_json(content)
          new(JsonValueParser.object(JsonValueParser.parse(content, "Pub package"), "Pub package"))
        end

        sig { params(data: JsonValueParser::ObjectHash).void }
        def initialize(data)
          @data = data
        end

        sig { returns(T::Array[Dependabot::Pub::Version]) }
        def versions
          version_entries(@data["versions"]).map do |fields|
            Dependabot::Pub::Version.new(JsonValueParser.string(fields["version"], "Pub package version"))
          end
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def releases
          version_entries(@data.fetch("versions", [])).map do |fields|
            Dependabot::Package::PackageRelease.new(
              version: Dependabot::Pub::Version.new(JsonValueParser.string(fields["version"], "Pub package version")),
              released_at: Time.parse(JsonValueParser.string(fields["published"], "Pub package published"))
            )
          end
        end

        sig { returns(T.nilable(String)) }
        def source_url
          latest = JsonValueParser.optional_object(@data["latest"], "Pub package latest")
          return unless latest

          pubspec = JsonValueParser.optional_object(latest["pubspec"], "Pub package latest.pubspec")
          return unless pubspec

          value = pubspec["repository"] || pubspec["homepage"]
          JsonValueParser.optional_string(value || nil, "Pub package repository or homepage")
        end

        private

        sig { params(value: Object).returns(T::Array[JsonValueParser::ObjectHash]) }
        def version_entries(value)
          JsonValueParser.array(value, "Pub package versions").each_with_index.map do |entry, index|
            JsonValueParser.object(entry, "Pub package versions[#{index}]")
          end
        end
      end
    end
  end
end
