# typed: strong
# frozen_string_literal: true

require "dependabot/pull_request_creator/message_components/pr_title"

module Dependabot
  class PullRequestCreator
    module MessageComponents
      # Generates PR titles for single dependency updates
      class SingleUpdateTitle < PrTitle
        extend T::Sig

        private

        sig { returns(String) }
        def base_title
          title = if library_pr?
                    library_title
                  else
                    application_title
                  end

          "#{title}#{directory_suffix}"
        end

        sig { returns(String) }
        def library_title
          "update " +
            if dependencies.one?
              dep = T.must(dependencies.first)
              "#{dep.display_name} requirement " \
                "#{from_version_msg(previous_requirement(dep))}to #{new_requirement(dep)}"
            else
              names = dependencies.map(&:name).uniq
              if names.one?
                "requirements for #{T.must(names.first)}"
              else
                "requirements for #{T.must(names[0..-2]).join(', ')} and #{T.must(names[-1])}"
              end
            end
        end

        sig { returns(String) }
        def application_title
          if dependencies.one?
            if updating_a_property?
              property_application_title
            elsif updating_a_dependency_set?
              dependency_set_application_title
            else
              single_dependency_application_title
            end
          elsif updating_a_property?
            property_application_title
          elsif updating_a_dependency_set?
            dependency_set_application_title
          else
            multiple_dependencies_application_title
          end
        end

        sig { returns(String) }
        def single_dependency_application_title
          dep = T.must(dependencies.first)
          "bump #{dep.display_name} " \
            "#{from_version_msg(dep.humanized_previous_version)}to #{dep.humanized_version}"
        end

        sig { returns(String) }
        def property_application_title
          dep = T.must(dependencies.first)
          prop_name = extract_property_name
          "bump #{prop_name} " \
            "#{from_version_msg(dep.humanized_previous_version)}to #{dep.humanized_version}"
        end

        sig { returns(String) }
        def dependency_set_application_title
          dep = T.must(dependencies.first)
          dep_set = extract_dependency_set
          "bump #{dep_set.fetch(:group)} dependency set " \
            "#{from_version_msg(dep.humanized_previous_version)}to #{dep.humanized_version}"
        end

        sig { returns(String) }
        def multiple_dependencies_application_title
          names = dependencies.map(&:name).uniq
          if names.one?
            "bump #{T.must(names.first)}"
          else
            "bump #{T.must(names[0..-2]).join(', ')} and #{T.must(names[-1])}"
          end
        end

        sig { params(version: T.nilable(String)).returns(String) }
        def from_version_msg(version)
          return "" unless version

          "from #{version} "
        end

        sig { returns(String) }
        def directory_suffix
          dir = options[:directory]
          return "" unless dir && dir != "/"

          " in #{dir}"
        end

        sig { returns(T::Boolean) }
        def library_pr?
          T.cast(options[:library], T::Boolean)
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
        def extract_property_name
          prop = T.must(dependencies.first)
                  .requirements
                  .find { |r| r.dig(:metadata, :property_name) }
                  &.dig(:metadata, :property_name)

          raise "No property name!" unless prop

          prop
        end

        sig { returns(T::Hash[Symbol, String]) }
        def extract_dependency_set
          dep_set = T.must(dependencies.first)
                     .requirements
                     .find { |r| r.dig(:metadata, :dependency_set) }
                     &.dig(:metadata, :dependency_set)

          raise "No dependency set!" unless dep_set

          T.cast(dep_set, T::Hash[Symbol, String])
        end

        sig { params(dep: Dependabot::Dependency).returns(T.nilable(String)) }
        def previous_requirement(dep)
          # Extract the old requirement for library updates
          old_reqs = T.must(dep.previous_requirements) - dep.requirements

          # Prefer gemspec requirements
          gemspec = old_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
          return T.cast(gemspec.fetch(:requirement), String) if gemspec

          req = T.must(old_reqs.first).fetch(:requirement)
          return T.cast(req, String) if req

          dep.previous_ref if dep.ref_changed?
        end

        sig { params(dep: Dependabot::Dependency).returns(String) }
        def new_requirement(dep)
          # Extract the new requirement for library updates
          updated_reqs = dep.requirements - T.must(dep.previous_requirements)

          # Prefer gemspec requirements
          gemspec = updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
          return T.cast(gemspec.fetch(:requirement), String) if gemspec

          req = T.must(updated_reqs.first).fetch(:requirement)
          return T.cast(req, String) if req
          return T.must(dep.new_ref) if dep.ref_changed? && dep.new_ref

          raise "No new requirement!"
        end
      end
    end
  end
end
