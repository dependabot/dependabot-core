# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/python/name_normaliser"
require "dependabot/python/package/distribution"

module Dependabot
  module Python
    module Package
      class SimpleApiParser
        extend T::Sig

        sig { params(dependency: Dependabot::Dependency, project_url: String).void }
        def initialize(dependency:, project_url:)
          @dependency = dependency
          @project_url = project_url
        end

        sig do
          params(json_body: String)
            .returns(T::Hash[String, T::Array[Distribution]])
        end
        def parse(json_body)
          context = Distribution.context("Simple API JSON", project_url)
          data = Distribution.object(Distribution.parse_json(json_body, context), context)
          meta = data["meta"]
          metadata = meta.nil? ? {} : Distribution.object(meta, "#{context}.meta")
          validate_api_version!(metadata.fetch("api-version", "1.0"), context)

          releases = T.let({}, T::Hash[String, T::Array[Distribution]])
          Distribution.array(data.fetch("files", []), "#{context}.files").each_with_index do |entry, index|
            location = "#{context}.files[#{index}]"
            file = Distribution.object(entry, location)
            filename = Distribution.optional_string(file["filename"], "#{location}.filename")
            next unless filename&.match?(name_regex)

            version = version_from_filename(filename)
            next unless version && dependency.version_class.correct?(version)

            distribution = Distribution.from_simple(
              file, version_string: version, context: location, project_url: project_url
            )
            releases[version] ||= []
            T.must(releases[version]) << distribution
          end
          releases
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(String) }
        attr_reader :project_url

        sig { params(api_version: Object, context: String).void }
        def validate_api_version!(api_version, context)
          unless api_version.is_a?(String) && api_version.match?(/\A[0-9]+\.[0-9]+\z/)
            Distribution.invalid("#{context}.meta.api-version", "must be a Major.Minor string")
          end
          return unless api_version.split(".").first.to_i > 1

          raise Dependabot::DependencyFileNotResolvable, "Unsupported PEP 691 API version: #{api_version}"
        end

        sig { returns(Regexp) }
        def name_regex
          parts = NameNormaliser.normalise(dependency.name).split(/[\s_.-]/).map { |name| Regexp.quote(name) }
          /#{parts.join("[\s_.-]")}/i
        end

        sig { params(filename: String).returns(T.nilable(String)) }
        def version_from_filename(filename)
          filename.strip.gsub(/#{name_regex}-/i, "").split(/-|\.tar\.|\.zip|\.whl/).first
        end
      end
    end
  end
end
