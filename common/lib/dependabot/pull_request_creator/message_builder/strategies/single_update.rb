# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/pull_request_creator/message_builder/strategies/base"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      module Strategies
        # Builds the base PR title for a single dependency update.
        class SingleUpdate < Base
          extend T::Sig

          sig { returns(T::Array[Dependabot::Dependency]) }
          attr_reader :dependencies

          sig { returns(T::Array[Dependabot::DependencyFile]) }
          attr_reader :files

          sig do
            params(
              dependencies: T::Array[Dependabot::Dependency],
              files: T::Array[Dependabot::DependencyFile]
            ).void
          end
          def initialize(dependencies:, files:)
            @dependencies = dependencies
            @files = files
          end

          sig { override.returns(String) }
          def base_title
            name = library? ? library_pr_name : application_pr_name
            "#{name}#{pr_name_directory}"
          end

          private

          sig { returns(String) }
          def library_pr_name
            "update " +
              if dependencies.one?
                "#{T.must(dependencies.first).display_name} requirement " \
                  "#{from_version_msg(old_library_requirement(T.must(dependencies.first)))}" \
                  "to #{new_library_requirement(T.must(dependencies.first))}"
              else
                names = dependencies.map(&:name).uniq
                if names.one?
                  "requirements for #{names.first}"
                else
                  "requirements for #{T.must(names[0..-2]).join(', ')} and #{names[-1]}"
                end
              end
          end

          sig { returns(String) }
          def application_pr_name
            "bump " +
              if dependencies.one?
                single_dep_application_name
              elsif updating_a_property?
                property_update_name
              elsif updating_a_dependency_set?
                dependency_set_update_name
              else
                multi_dep_names
              end
          end

          sig { returns(String) }
          def single_dep_application_name
            dependency = T.must(dependencies.first)
            "#{dependency.display_name} " \
              "#{from_version_msg(dependency.humanized_previous_version)}" \
              "to #{dependency.humanized_version}"
          end

          sig { returns(String) }
          def property_update_name
            dependency = T.must(dependencies.first)
            "#{property_name} " \
              "#{from_version_msg(dependency.humanized_previous_version)}" \
              "to #{dependency.humanized_version}"
          end

          sig { returns(String) }
          def dependency_set_update_name
            dependency = T.must(dependencies.first)
            "#{dependency_set.fetch(:group)} dependency set " \
              "#{from_version_msg(dependency.humanized_previous_version)}" \
              "to #{dependency.humanized_version}"
          end

          sig { returns(String) }
          def multi_dep_names
            names = dependencies.map(&:name).uniq
            if names.one?
              T.must(names.first)
            else
              "#{T.must(names[0..-2]).join(', ')} and #{names[-1]}"
            end
          end

          sig { returns(T::Boolean) }
          def library?
            root_files = files.map(&:name)
                              .select { |p| Pathname.new(p).dirname.to_s == "." }
            return true if root_files.any? { |nm| nm.end_with?(".gemspec") }

            dependencies.any? { |d| d.humanized_previous_version.nil? }
          end

          sig { params(previous_version: T.nilable(String)).returns(String) }
          def from_version_msg(previous_version)
            return "" unless previous_version

            "from #{previous_version} "
          end

          sig { returns(String) }
          def pr_name_directory
            directory = T.must(files.first).directory
            return "" if directory == "/"

            " in #{directory}"
          end

          sig { returns(T::Boolean) }
          def updating_a_property?
            T.must(dependencies.first)
             .requirements
             .any? { |r| r.dig(:metadata, :property_name) }
          end

          sig { returns(T::Boolean) }
          def updating_a_dependency_set?
            T.must(dependencies.first)
             .requirements
             .any? { |r| r.dig(:metadata, :dependency_set) }
          end

          sig { returns(String) }
          def property_name
            @property_name ||=
              T.let(
                dependencies.first
                  &.requirements
                  &.find { |r| r.dig(:metadata, :property_name) }
                  &.dig(:metadata, :property_name),
                T.nilable(String)
              )

            raise "No property name!" unless @property_name

            @property_name
          end

          sig { returns(T::Hash[Symbol, String]) }
          def dependency_set
            @dependency_set ||=
              T.let(
                dependencies.first
                  &.requirements
                  &.find { |r| r.dig(:metadata, :dependency_set) }
                  &.dig(:metadata, :dependency_set),
                T.nilable(T.nilable(T::Hash[Symbol, String]))
              )

            raise "No dependency set!" unless @dependency_set

            @dependency_set
          end

          sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
          def old_library_requirement(dependency)
            old_reqs =
              T.must(dependency.previous_requirements) - dependency.requirements

            gemspec =
              old_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
            return gemspec.fetch(:requirement) if gemspec

            req = T.must(old_reqs.first).fetch(:requirement)
            return req if req

            dependency.previous_ref if dependency.ref_changed?
          end

          sig { params(dependency: Dependabot::Dependency).returns(String) }
          def new_library_requirement(dependency)
            updated_reqs =
              dependency.requirements - T.must(dependency.previous_requirements)

            gemspec =
              updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
            return gemspec.fetch(:requirement) if gemspec

            req = T.must(updated_reqs.first).fetch(:requirement)
            return req if req
            return T.must(dependency.new_ref) if dependency.ref_changed? && dependency.new_ref

            raise "No new requirement!"
          end
        end
      end
    end
  end
end
