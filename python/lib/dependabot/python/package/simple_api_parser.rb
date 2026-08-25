# typed: strict
# frozen_string_literal: true

require "json"
require "uri"
require "sorbet-runtime"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    module Package
      class SimpleApiParser
        extend T::Sig

        ReleaseDetail = T.type_alias { T::Hash[String, T.nilable(T.any(String, T::Boolean))] }

        sig { params(dependency: Dependabot::Dependency, project_url: String).void }
        def initialize(dependency:, project_url:)
          @dependency = dependency
          @project_url = project_url
        end

        sig do
          params(json_body: String)
            .returns(T::Hash[String, T::Array[ReleaseDetail]])
        end
        def parse(json_body)
          JSON.parse(json_body).fetch("files", []).each_with_object({}) do |file, releases|
            filename = file["filename"]
            next unless filename&.match?(name_regex)

            version = version_from_filename(filename)
            next unless dependency.version_class.correct?(version)

            yanked = file["yanked"] || false
            details = {
              "version" => version,
              "requires_python" => file["requires-python"],
              "yanked" => !!yanked,
              "yanked_reason" => yanked.is_a?(String) ? yanked : nil,
              "url" => resolve_url(file["url"])
            }
            releases[version] ||= []
            releases[version] << details
          end
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(String) }
        attr_reader :project_url

        sig { params(url: T.nilable(String)).returns(T.nilable(String)) }
        def resolve_url(url)
          URI.join(project_url, url).to_s if url
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
