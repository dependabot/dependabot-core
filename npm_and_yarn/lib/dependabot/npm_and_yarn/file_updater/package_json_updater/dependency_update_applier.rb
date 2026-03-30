# typed: strict
# frozen_string_literal: true

require "dependabot/npm_and_yarn/file_updater/package_json_updater"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      class PackageJsonUpdater
        class DependencyUpdateApplier
          extend T::Sig

          sig do
            params(
              updater: Dependabot::NpmAndYarn::FileUpdater::PackageJsonUpdater,
              content: String,
              dependency: Dependabot::Dependency,
              unique_deps_count: Integer
            ).void
          end
          def initialize(updater:, content:, dependency:, unique_deps_count:)
            @updater = updater
            @content = content
            @dependency = dependency
            @unique_deps_count = unique_deps_count
          end

          sig { returns(String) }
          def updated_content
            updated_content = apply_requirement_updates(content)
            updated_content = apply_resolution_updates(updated_content)
            return updated_content unless dependency.previous_version && new_requirements.empty?

            apply_subdependency_updates(updated_content)
          end

          private

          sig { returns(Dependabot::NpmAndYarn::FileUpdater::PackageJsonUpdater) }
          attr_reader :updater

          sig { returns(String) }
          attr_reader :content

          sig { returns(Dependabot::Dependency) }
          attr_reader :dependency

          sig { returns(Integer) }
          attr_reader :unique_deps_count

          sig { params(current_content: String).returns(String) }
          def apply_requirement_updates(current_content)
            updated_requirements&.each do |new_req|
              next_content = update_package_json_declaration(
                package_json_content: current_content,
                dependency_name: dependency.name,
                old_req: old_requirement(new_req),
                new_req: new_req
              )

              raise "Expected content to change!" if current_content == next_content && unique_deps_count > 1

              current_content = next_content
            end

            current_content
          end

          sig { params(current_content: String).returns(String) }
          def apply_resolution_updates(current_content)
            new_requirements.each do |new_req|
              current_content = update_package_json_resolutions(
                package_json_content: current_content,
                new_req: new_req,
                dependency: dependency,
                old_req: old_requirement(new_req)
              )
            end

            current_content
          end

          sig { params(current_content: String).returns(String) }
          def apply_subdependency_updates(current_content)
            updated_content = update_overrides_for_subdependency(
              package_json_content: current_content,
              dependency: dependency
            )
            return updated_content unless updated_content == current_content

            Dependabot::NpmAndYarn::FileUpdater::PackageJsonUpdater::PnpmOverrideHelper.new(
              package_json_content: current_content,
              dependency: dependency,
              detected_package_manager: detected_package_manager
            ).updated_content
          end

          sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
          def updated_requirements
            updater.send(:updated_requirements, dependency)
          end

          sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
          def new_requirements
            updater.send(:new_requirements, dependency)
          end

          sig { params(new_req: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
          def old_requirement(new_req)
            updater.send(:old_requirement, dependency, new_req)
          end

          sig do
            params(
              package_json_content: String,
              dependency_name: String,
              old_req: T.nilable(T::Hash[Symbol, T.untyped]),
              new_req: T::Hash[Symbol, T.untyped]
            ).returns(String)
          end
          def update_package_json_declaration(package_json_content:, dependency_name:, old_req:, new_req:)
            updater.send(
              :update_package_json_declaration,
              package_json_content: package_json_content,
              dependency_name: dependency_name,
              old_req: old_req,
              new_req: new_req
            )
          end

          sig do
            params(
              package_json_content: String,
              new_req: T::Hash[Symbol, T.untyped],
              dependency: Dependabot::Dependency,
              old_req: T.nilable(T::Hash[Symbol, T.untyped])
            ).returns(String)
          end
          def update_package_json_resolutions(package_json_content:, new_req:, dependency:, old_req:)
            updater.send(
              :update_package_json_resolutions,
              package_json_content: package_json_content,
              new_req: new_req,
              dependency: dependency,
              old_req: old_req
            )
          end

          sig { params(package_json_content: String, dependency: Dependabot::Dependency).returns(String) }
          def update_overrides_for_subdependency(package_json_content:, dependency:)
            updater.send(
              :update_overrides_for_subdependency,
              package_json_content: package_json_content,
              dependency: dependency
            )
          end

          sig { returns(T.nilable(String)) }
          def detected_package_manager
            updater.send(:detected_package_manager)
          end
        end
      end
    end
  end
end
