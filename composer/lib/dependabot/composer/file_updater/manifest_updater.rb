# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/composer/file_updater"

module Dependabot
  module Composer
    class FileUpdater
      class ManifestUpdater
        extend T::Sig

        sig { params(dependencies: T::Array[Dependabot::Dependency], manifest: Dependabot::DependencyFile).void }
        def initialize(dependencies:, manifest:)
          @dependencies = dependencies
          @manifest = manifest
        end

        sig { returns(String) }
        def updated_manifest_content
          T.must(
            dependencies.reduce(manifest.content.dup) do |content, dep|
              updated_content = content
              updated_requirements(dep).each do |new_req|
                old_req = old_requirement(dep, new_req)&.fetch(:requirement)
                updated_req = new_req.fetch(:requirement)

                regex =
                  /
                    "#{Regexp.escape(dep.name)}"\s*:\s*
                    "#{Regexp.escape(old_req)}"
                  /x

                updated_content = content&.gsub(regex) do |declaration|
                  declaration.gsub(%("#{old_req}"), %("#{updated_req}"))
                end

                raise "Expected content to change!" if content == updated_content
              end

              updated_content
            end
          )
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { params(dependency: Dependabot::Dependency).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def new_requirements(dependency)
          dependency.requirements.select { |r| r[:file] == manifest.name }
        end

        sig do
          params(
            dependency: Dependabot::Dependency,
            new_requirement: T::Hash[Symbol, T.untyped]
          )
            .returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def old_requirement(dependency, new_requirement)
          T.must(dependency.previous_requirements)
           .select { |r| r[:file] == manifest.name }
           .find { |r| r[:groups] == new_requirement[:groups] }
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements(dependency)
          new_requirements(dependency)
            .reject { |r| T.must(dependency.previous_requirements).include?(r) }
        end

        sig { params(file: Dependabot::DependencyFile, dependency: Dependabot::Dependency).returns(T::Boolean) }
        def requirement_changed?(file, dependency)
          changed_requirements =
            dependency.requirements - T.must(dependency.previous_requirements)

          changed_requirements.any? { |f| f[:file] == file.name }
        end
      end
    end
  end
end
