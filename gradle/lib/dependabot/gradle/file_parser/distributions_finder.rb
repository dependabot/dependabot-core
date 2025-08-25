# typed: strong
# frozen_string_literal: true

require "dependabot/gradle/file_parser"
require "dependabot/gradle/distributions"
require "sorbet-runtime"

module Dependabot
  module Gradle
    class FileParser
      class DistributionsFinder
        extend T::Sig
        include Dependabot::Gradle::Distributions

        DISTRIBUTION_URL_REGEX = %r{
          ^#{Regexp.escape(DISTRIBUTIONS_URL)}/distributions/
          gradle-(?<version>[\d.]+)-
          (?<distribution_type>bin|all)\.zip$
        }x

        sig { params(properties_file: DependencyFile).returns(T.nilable(Dependency)) }
        def self.resolve_dependency(properties_file)
          content = properties_file.content
          return nil unless content

          distribution_url, checksum = load_properties(content)
          match = distribution_url&.match(DISTRIBUTION_URL_REGEX)&.named_captures
          return nil unless match

          version = match.fetch("version")

          requirements = T.let([{
            requirement: version,
            file: properties_file.name,
            source: {
              type: DISTRIBUTION_DEPENDENCY_TYPE,
              url: distribution_url,
              property: "distributionUrl"
            },
            groups: []
          }], T::Array[T::Hash[Symbol, T.untyped]])

          if checksum
            requirements << {
              requirement: checksum,
              file: properties_file.name,
              source: {
                type: DISTRIBUTION_DEPENDENCY_TYPE,
                url: "#{distribution_url}.sha256",
                property: "distributionSha256Sum"
              },
              groups: []
            }
          end

          Dependency.new(
            name: "gradle-wrapper",
            version: version,
            requirements: requirements,
            package_manager: "gradle"
          )
        end

        sig { params(properties_content: String).returns(T::Array[T.nilable(String)]) }
        def self.load_properties(properties_content)
          distribution_url = T.let(nil, T.nilable(String))
          checksum = T.let(nil, T.nilable(String))

          properties_content.lines.each do |line|
            (key, value) = line.split("=", 2).map(&:strip)
            next unless key && value

            case key
            when "distributionUrl"
              distribution_url = value.gsub("\\:", ":")
            when "distributionSha256Sum"
              checksum = value
            else
              next
            end
            break if distribution_url && checksum
          end

          [distribution_url, checksum]
        end

        private_class_method :load_properties
      end
    end
  end
end
