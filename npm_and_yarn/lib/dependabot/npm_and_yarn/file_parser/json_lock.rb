# typed: strict
# frozen_string_literal: true

require "json"
require "dependabot/errors"
require "dependabot/npm_and_yarn/helpers"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      class JsonLock
        extend T::Sig

        sig { params(dependency_file: DependencyFile).void }
        def initialize(dependency_file)
          @dependency_file = dependency_file
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed
          json_obj = JSON.parse(T.must(@dependency_file.content))
          @parsed ||= T.let(json_obj, T.untyped)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, @dependency_file.path
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependencies
          recursively_fetch_dependencies(parsed)
        end

        sig do
          params(dependency_name: String, _requirement: T.untyped, manifest_name: String)
            .returns(T.nilable(T::Hash[String, T.untyped]))
        end
        def details(dependency_name, _requirement, manifest_name)
          if Helpers.npm8?(@dependency_file)
            # NOTE: npm 8 sometimes doesn't install workspace dependencies in the
            # workspace folder so we need to fallback to checking top-level
            nested_details = parsed.dig("packages", node_modules_path(manifest_name, dependency_name))
            details = nested_details || parsed.dig("packages", "node_modules/#{dependency_name}")
            details&.slice("version", "resolved", "integrity", "dev")
          else
            parsed.dig("dependencies", dependency_name)
          end
        end

        private

        sig do
          params(object_with_dependencies: T::Hash[String, T.untyped])
            .returns(Dependabot::FileParsers::Base::DependencySet)
        end
        def recursively_fetch_dependencies(object_with_dependencies)
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          dependencies = object_with_dependencies["dependencies"]
          dependencies ||= object_with_dependencies.fetch("packages", {})

          dependencies.each do |name, details|
            next if name.empty? # v3 lockfiles include an empty key holding info of the current package

            version = Version.semver_for(details["version"])
            next unless version

            version = version.to_s

            dependency_args = {
              name: name.split("node_modules/").last,
              version: version,
              package_manager: "npm_and_yarn",
              requirements: []
            }

            if details["bundled"]
              dependency_args[:subdependency_metadata] =
                [{ npm_bundled: details["bundled"] }]
            end

            if details["dev"]
              dependency_args[:subdependency_metadata] =
                [{ production: !details["dev"] }]
            end

            dependency_set << Dependency.new(**dependency_args)
            dependency_set += recursively_fetch_dependencies(details)
          end

          dependency_set
        end

        sig { params(manifest_name: String, dependency_name: String).returns(String) }
        def node_modules_path(manifest_name, dependency_name)
          return "node_modules/#{dependency_name}" if manifest_name == "package.json"

          workspace_path = manifest_name.gsub("/package.json", "")
          File.join(workspace_path, "node_modules", dependency_name)
        end
      end
    end
  end
end
