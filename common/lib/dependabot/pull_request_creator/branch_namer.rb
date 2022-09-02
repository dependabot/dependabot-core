# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class BranchNamer
      attr_reader :dependencies, :files, :target_branch, :separator, :prefix

      def initialize(dependencies:, files:, target_branch:, separator: "/",
                     prefix: "dependabot")
        @dependencies  = dependencies
        @files         = files
        @target_branch = target_branch
        @separator     = separator
        @prefix        = prefix
      end

      def new_branch_name
        @name ||=
          begin
            dependency_name_part =
              if dependencies.count > 1 && updating_a_property?
                property_name
              elsif dependencies.count > 1 && updating_a_dependency_set?
                dependency_set.fetch(:group)
              else
                dependencies.
                  map(&:name).
                  join("-and-").
                  tr(":[]", "-").
                  tr("@", "")
              end

            "#{dependency_name_part}-#{branch_version_suffix}"
          end

        # Some users need branch names without slashes
        sanitize_ref(File.join(prefixes, @name).gsub("/", separator))
      end

      private

      def prefixes
        [
          prefix,
          package_manager,
          files.first.directory.tr(" ", "-"),
          target_branch
        ].compact
      end

      def package_manager
        dependencies.first.package_manager
      end

      def updating_a_property?
        dependencies.first.
          requirements.
          any? { |r| r.dig(:metadata, :property_name) }
      end

      def updating_a_dependency_set?
        dependencies.first.
          requirements.
          any? { |r| r.dig(:metadata, :dependency_set) }
      end

      def property_name
        @property_name ||= dependencies.first.requirements.
                           find { |r| r.dig(:metadata, :property_name) }&.
                           dig(:metadata, :property_name)

        raise "No property name!" unless @property_name

        @property_name
      end

      def dependency_set
        @dependency_set ||= dependencies.first.requirements.
                            find { |r| r.dig(:metadata, :dependency_set) }&.
                            dig(:metadata, :dependency_set)

        raise "No dependency set!" unless @dependency_set

        @dependency_set
      end

      def branch_version_suffix
        dep = dependencies.first

        if dep.removed?
          ""
        elsif library? && ref_changed?(dep) && new_ref(dep)
          new_ref(dep)
        elsif library?
          sanitized_requirement(dep)
        else
          new_version(dep)
        end
      end

      def sanitized_requirement(dependency)
        new_library_requirement(dependency).
          delete(" ").
          gsub("!=", "neq-").
          gsub(">=", "gte-").
          gsub("<=", "lte-").
          gsub("~>", "tw-").
          gsub("^", "tw-").
          gsub("||", "or-").
          gsub("~", "approx-").
          gsub("~=", "tw-").
          gsub(/==*/, "eq-").
          gsub(">", "gt-").
          gsub("<", "lt-").
          gsub("*", "star").
          gsub(",", "-and-")
      end

      def new_version(dependency)
        # Version looks like a git SHA and we could be updating to a specific
        # ref in which case we return that otherwise we return a shorthand sha
        if dependency.version.match?(/^[0-9a-f]{40}$/)
          return new_ref(dependency) if ref_changed?(dependency) && new_ref(dependency)

          dependency.version[0..6]
        elsif dependency.version == dependency.previous_version &&
              package_manager == "docker"
          dependency.requirements.
            map { |r| r.dig(:source, "digest") || r.dig(:source, :digest) }.
            compact.first.split(":").last[0..6]
        else
          dependency.version
        end
      end

      def previous_ref(dependency)
        previous_refs = dependency.previous_requirements.map do |r|
          r.dig(:source, "ref") || r.dig(:source, :ref)
        end.compact.uniq
        return previous_refs.first if previous_refs.count == 1
      end

      def new_ref(dependency)
        new_refs = dependency.requirements.map do |r|
          r.dig(:source, "ref") || r.dig(:source, :ref)
        end.compact.uniq
        return new_refs.first if new_refs.count == 1
      end

      def ref_changed?(dependency)
        # We could go from multiple previous refs (nil) to a single new ref
        previous_ref(dependency) != new_ref(dependency)
      end

      def new_library_requirement(dependency)
        updated_reqs =
          dependency.requirements - dependency.previous_requirements

        gemspec =
          updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
        return gemspec[:requirement] if gemspec

        updated_reqs.first[:requirement]
      end

      # TODO: Bring this in line with existing library checks that we do in the
      # update checkers, which are also overriden by passing an explicit
      # `requirements_update_strategy`.
      #
      # TODO re-use in MessageBuilder
      def library?
        dependencies.any? { |d| !d.appears_in_lockfile? }
      end

      def requirements_changed?(dependency)
        (dependency.requirements - dependency.previous_requirements).any?
      end

      def sanitize_ref(ref)
        # This isn't a complete implementation of git's ref validation, but it
        # covers most cases that crop up. Its list of allowed charactersr is a
        # bit stricter than git's, but that's for cosmetic reasons.
        ref.
          # Remove forbidden characters (those not already replaced elsewhere)
          gsub(%r{[^A-Za-z0-9/\-_.(){}]}, "").
          # Slashes can't be followed by periods
          gsub(%r{/\.}, "/dot-").
          # Two or more sequential periods are forbidden
          gsub(/\.+/, ".").
          # Two or more sequential slashes are forbidden
          gsub(%r{/+}, "/").
          # Trailing periods are forbidden
          sub(/\.$/, "")
      end
    end
  end
end
