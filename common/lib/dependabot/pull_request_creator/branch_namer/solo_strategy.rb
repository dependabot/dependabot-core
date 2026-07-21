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
          if template
            return render_from_template(
              vars: template_vars,
              strategy: :solo
            )
          end

          return short_branch_name if branch_name_might_be_long?

          @name ||=
            T.let(
              "#{template_dependency_name}-#{branch_version_suffix}",
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

        sig { returns(T::Hash[String, String]) }
        def template_vars
          dep_name = template_dependency_name
          version = branch_version_suffix || ""

          vars = {
            "prefix" => prefix,
            "package_manager" => package_manager,
            "directory" => sanitized_directory,
            "dependency" => dep_name,
            "version" => version,
            "name" => "#{dep_name}-#{version}",
            "target_branch" => target_branch || ""
          }
          vars
        end

        sig { returns(String) }
        def template_dependency_name
          if dependencies.count > 1 && updating_a_property?
            property_name
          elsif dependencies.count > 1 && updating_a_dependency_set?
            dependency_set.fetch(:group)
          else
            dependencies.map(&:name).join("-and-").tr(":[]", "-").tr("@", "")
          end
        end

        sig { returns(String) }
        def sanitized_directory
          dir = (files.first&.directory&.tr(" ", "-") || "/").sub(%r{^/}, "")
          dir.empty? ? "root" : dir
        end

        sig { returns(String) }
        def package_manager
          T.must(dependencies.first).package_manager
        end

        sig { returns(T::Boolean) }
        def updating_a_property?
          T.must(dependencies.first)
           .requirements
           .any? { |requirement| requirement.metadata&.key?(:property_name) }
        end

        sig { returns(T::Boolean) }
        def updating_a_dependency_set?
          T.must(dependencies.first)
           .requirements
           .any? { |requirement| requirement.metadata&.key?(:dependency_set) }
        end

        sig { returns(String) }
        def property_name
          @property_name ||=
            T.let(
              T.must(dependencies.first).requirements
                                              .filter_map do |requirement|
                                                metadata_string(requirement, :property_name)
                                              end
                                              .first,
              T.nilable(String)
            )

          raise "No property name!" unless @property_name

          @property_name
        end

        sig { returns(T::Hash[Symbol, String]) }
        def dependency_set
          @dependency_set ||=
            T.let(
              T.must(dependencies.first).requirements
                                 .filter_map do |requirement|
                                   metadata_string_hash(requirement, :dependency_set)
                                 end
                                 .first,
              T.nilable(T::Hash[Symbol, String])
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
          T.must(new_library_requirement(dependency))
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
            digests = dependency.requirements.filter_map do |requirement|
              source_string(requirement, "digest")
            end
            T.must(T.must(digests.first).split(":").last)[0..6]
          else
            dependency.version
          end
        end

        sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
        def previous_ref(dependency)
          dependency.previous_ref
        end

        sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
        def new_ref(dependency)
          dependency.new_ref
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def ref_changed?(dependency)
          # We could go from multiple previous refs (nil) to a single new ref
          previous_ref(dependency) != new_ref(dependency)
        end

        sig { params(dependency: Dependabot::Dependency).returns(T.nilable(String)) }
        def new_library_requirement(dependency)
          updated_reqs =
            dependency.requirements - T.must(dependency.previous_requirements)

          gemspec =
            updated_reqs.find { |requirement| requirement.file&.match?(%r{^[^/]*\.gemspec$}) }
          return gemspec.requirement if gemspec

          updated_reqs.first&.requirement
        end

        sig do
          params(
            requirement: Dependabot::DependencyRequirement,
            key: Symbol
          ).returns(T.nilable(String))
        end
        def metadata_string(requirement, key)
          value = requirement.metadata&.[](key)
          value if value.is_a?(String)
        end

        sig do
          params(
            requirement: Dependabot::DependencyRequirement,
            key: Symbol
          ).returns(T.nilable(T::Hash[Symbol, String]))
        end
        def metadata_string_hash(requirement, key)
          value = requirement.metadata&.[](key)
          return unless value.is_a?(Hash)

          value.each_with_object(T.let({}, T::Hash[Symbol, String])) do |(raw_key, raw_value), result|
            parsed_key = T.cast(raw_key, Object)
            unless (parsed_key.is_a?(String) || parsed_key.is_a?(Symbol)) && raw_value.is_a?(String)
              raise TypeError, "#{key} metadata must be a string-valued hash"
            end

            result[parsed_key.to_sym] = raw_value
          end
        end

        sig { params(requirement: Dependabot::DependencyRequirement, key: String).returns(T.nilable(String)) }
        def source_string(requirement, key)
          source = requirement.source
          return unless source

          value = source[key] || source[key.to_sym]
          value if value.is_a?(String)
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
            Digest::MD5.hexdigest(
              dependencies.map do |dependency|
                "#{dependency.name}-#{dependency.removed? ? 'removed' : dependency.version}"
              end.sort.join(",")
            ).slice(0, 10),
            T.nilable(String)
          )
        end
      end
    end
  end
end
