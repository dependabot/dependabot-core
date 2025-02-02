# typed: strict
# frozen_string_literal: true

require "digest"
require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/pull_request_creator/branch_namer/base"

module Dependabot
  class PullRequestCreator
    class BranchNamer
      class SoloStrategy < Base
        extend T::Sig

        sig { override.returns(String) }
        def new_branch_name
          return short_branch_name if branch_name_might_be_long?

          @name ||=
            T.let(
              begin
                dependency_name_part =
                  if dependencies.count > 1 && updating_a_property?
                    property_name
                  elsif dependencies.count > 1 && updating_a_dependency_set?
                    dependency_set.fetch(:group)
                  else
                    dependencies
                      .map(&:name)
                      .join("-and-")
                      .tr(":[]", "-")
                      .tr("@", "")
                  end

                "#{dependency_name_part}-#{branch_version_suffix}"
              end,
              T.nilable(String)
            )

          sanitize_branch_name(File.join(prefixes, @name))
        end

        private

        sig { returns(T::Array[String]) }
        def prefixes
          [
            prefix,
            package_manager,
            files.first&.directory&.tr(" ", "-"),
            target_branch
          ].compact
        end

        sig { returns(String) }
        def package_manager
          T.must(dependencies.first).package_manager
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
            T.let(T.must(dependencies.first).requirements
                                .find { |r| r.dig(:metadata, :property_name) }
                                &.dig(:metadata, :property_name),
                  T.nilable(String))

          raise "No property name!" unless @property_name

          @property_name
        end

        sig { returns(T::Hash[Symbol, String]) }
        def dependency_set
          @dependency_set ||=
            T.let(
              T.must(dependencies.first).requirements
                                 .find { |r| r.dig(:metadata, :dependency_set) }
                                 &.dig(:metadata, :dependency_set),
              T.nilable(T::Hash[String, String])
            )

          raise "No dependency set!" unless @dependency_set

          @dependency_set
        end

        sig { returns(T.nilable(String)) }
        def branch_version_suffix
          dep = T.must(dependencies.first)

          if dep.removed?
            "-removed"
          elsif library? && ref_changed?(dep) && new_ref(dep)
            new_ref(dep)
          elsif library?
            sanitized_requirement(dep)
          else
            new_version(dep)
          end
        end

        sig { params(dependency: Dependabot::Dependency).returns(String) }
        def sanitized_requirement(dependency)
          new_library_requirement(dependency)
            .delete(" ")
            .gsub("!=", "neq-")
            .gsub(">=", "gte-")
            .gsub("<=", "lte-")
            .gsub("~>", "tw-")
            .gsub("^", "tw-")
            .gsub("||", "or-")
            .gsub("~", "approx-")
            .gsub("~=", "tw-")
            .gsub(/==*/, "eq-")
            .gsub(">", "gt-")
            .gsub("<", "lt-")
            .gsub("*", "star")
            .gsub(",", "-and-")
        end

        sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
        def new_version(dependency)
          # Version looks like a git SHA and we could be updating to a specific
          # ref in which case we return that otherwise we return a shorthand sha
          if dependency.version&.match?(/^[0-9a-f]{40}$/)
            return new_ref(dependency) if ref_changed?(dependency) && new_ref(dependency)

            T.must(dependency.version)[0..6]
          elsif dependency.version == dependency.previous_version &&
                package_manager == "docker"
            dependency.requirements
                      .filter_map { |r| r.dig(:source, "digest") || r.dig(:source, :digest) }
                      .first.split(":").last[0..6]
          else
            dependency.version
          end
        end

        sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
        def previous_ref(dependency)
          previous_refs = T.must(dependency.previous_requirements).filter_map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.uniq
          previous_refs.first if previous_refs.count == 1
        end

        sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
        def new_ref(dependency)
          new_refs = dependency.requirements.filter_map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.uniq
          new_refs.first if new_refs.count == 1
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def ref_changed?(dependency)
          # We could go from multiple previous refs (nil) to a single new ref
          previous_ref(dependency) != new_ref(dependency)
        end

        sig { params(dependency: Dependabot::Dependency).returns(T.untyped) }
        def new_library_requirement(dependency)
          updated_reqs =
            dependency.requirements - T.must(dependency.previous_requirements)

          gemspec =
            updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
          return gemspec[:requirement] if gemspec

          updated_reqs.first&.fetch(:requirement)
        end

        # TODO: Bring this in line with existing library checks that we do in the
        # update checkers, which are also overridden by passing an explicit
        # `requirements_update_strategy`.
        #
        # TODO reuse in MessageBuilder
        sig { returns(T::Boolean) }
        def library?
          dependencies.any? { |d| !d.appears_in_lockfile? }
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def requirements_changed?(dependency)
          (dependency.requirements - T.must(dependency.previous_requirements)).any?
        end

        sig { returns(T::Boolean) }
        def branch_name_might_be_long?
          dependencies.count > 1 && !updating_a_property? && !updating_a_dependency_set?
        end

        sig { returns(String) }
        def short_branch_name
          # Fix long branch names by using a digest of the dependencies instead of their names.
          sanitize_branch_name(File.join(prefixes, "multi-#{dependency_digest}"))
        end

        sig { returns(T.nilable(String)) }
        def dependency_digest
          T.let(
            Digest::MD5.hexdigest(dependencies.map do |dependency|
              "#{dependency.name}-#{dependency.removed? ? 'removed' : dependency.version}"
            end.sort.join(",")).slice(0, 10),
            T.nilable(String)
          )
        end
      end
    end
  end
end
