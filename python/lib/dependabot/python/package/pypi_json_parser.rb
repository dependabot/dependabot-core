# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/version"
require "dependabot/python/package/distribution"

module Dependabot
  module Python
    module Package
      class PypiJsonParser
        extend T::Sig

        sig { params(source_url: String).void }
        def initialize(source_url:)
          @context = T.let(Distribution.context("PyPI JSON", source_url), String)
        end

        sig { params(content: String).returns(T::Hash[String, T::Array[Distribution]]) }
        def parse(content)
          fields = Distribution.object(Distribution.parse_json(content, @context), @context)
          raw_releases = fields["releases"]
          return {} if raw_releases.nil?

          releases = Distribution.object(raw_releases, "#{@context}.releases")
          parsed = T.let({}, T::Hash[String, T::Array[Distribution]])
          releases.each_with_index do |(version, value), release_index|
            location = "#{@context}.releases[#{release_index}]"
            entries = Distribution.array(value, location)
            next if entries.empty?

            unless Python::Version.correct?(version)
              Dependabot.logger.warn("Skipping invalid version #{version}: does not match PEP 440")
              next
            end

            parsed[version] = entries.each_with_index.map do |entry, index|
              Distribution.from_pypi(
                entry, version_string: version, context: "#{location}[#{index}]"
              )
            end
          end
          parsed
        end
      end
    end
  end
end
