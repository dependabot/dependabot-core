# typed: strict
# frozen_string_literal: true

require "json"
require "excon"
require "toml-rb"
require "dependabot/registry_client"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class UpdateChecker
      # Lightweight helper for determining if a pyproject represents a library.
      class LibraryDetector
        extend T::Sig

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { returns(T::Boolean) }
        def library?
          pyproject = @dependency_files.find { |f| f.name == "pyproject.toml" }
          return false unless pyproject

          details = project_details(pyproject)
          return false unless details

          name = details["name"]
          return false if name.nil?

          description = details["description"]
          return false if description.nil?

          index_response = Dependabot::RegistryClient.get(
            url: "https://pypi.org/pypi/#{normalised_name(name)}/json/"
          )
          return false unless index_response.status == 200

          pypi_info = JSON.parse(index_response.body)["info"] || {}
          pypi_info["summary"] == description
        rescue Excon::Error::Timeout, Excon::Error::Socket, URI::InvalidURIError
          false
        end

        private

        sig { params(name: String).returns(String) }
        def normalised_name(name)
          NameNormaliser.normalise(name)
        end

        sig { params(pyproject: Dependabot::DependencyFile).returns(T.nilable(T::Hash[String, T.untyped])) }
        def project_details(pyproject)
          content = TomlRB.parse(pyproject.content)
          # Prefer poetry tool config then standard project metadata then build-system
          poetry = content.dig("tool", "poetry")
          return poetry if poetry

          standard = content["project"]
          return standard if standard

          content["build-system"]
        end
      end
    end
  end
end
