# typed: strict
# frozen_string_literal: true

################################################################################
# For more details on Composer version constraints, see:                       #
# https://getcomposer.org/doc/articles/versions.md#writing-version-constraints #
################################################################################

require "sorbet-runtime"

require "dependabot/composer/requirement"
require "dependabot/composer/update_checker"
require "dependabot/composer/version"
require "dependabot/requirements_update_strategy"

module Dependabot
  module Composer
    class UpdateChecker
      class RequirementsUpdater
        extend T::Sig

        ALIAS_REGEX = /[a-z0-9\-_\.]*\sas\s+/
        VERSION_REGEX = /(?:#{ALIAS_REGEX})?[0-9]+(?:\.[a-zA-Z0-9*\-]+)*/
        AND_SEPARATOR = /(?<=[a-zA-Z0-9*])(?<!\sas)[\s,]+(?![\s,]*[|-]|as)/
        OR_SEPARATOR = /(?<=[a-zA-Z0-9*])[\s,]*\|\|?\s*/
        SEPARATOR = /(?:#{AND_SEPARATOR})|(?:#{OR_SEPARATOR})/
        ALLOWED_UPDATE_STRATEGIES = T.let(
          [
            RequirementsUpdateStrategy::LockfileOnly,
            RequirementsUpdateStrategy::WidenRanges,
            RequirementsUpdateStrategy::BumpVersions,
            RequirementsUpdateStrategy::BumpVersionsIfNecessary
          ].freeze,
          T::Array[Dependabot::RequirementsUpdateStrategy]
        )

        sig do
          params(
            requirements: T::Array[T::Hash[Symbol, String]],
            update_strategy: Dependabot::RequirementsUpdateStrategy,
            latest_resolvable_version: T.nilable(T.any(String, Composer::Version))
          ).void
        end
        def initialize(requirements:, update_strategy:,
                       latest_resolvable_version:)
          @requirements = requirements
          @update_strategy = update_strategy

          check_update_strategy

          return unless latest_resolvable_version

          @latest_resolvable_version = T.let(
            version_class.new(latest_resolvable_version),
            Dependabot::Version
          )
        end

        sig { returns(T::Array[T::Hash[Symbol, String]]) }
        def updated_requirements
          return requirements if update_strategy.lockfile_only?
          return requirements unless latest_resolvable_version

          requirements.map { |req| updated_requirement(req) }
        end

        private

        sig { returns(T::Array[T::Hash[Symbol, String]]) }
        attr_reader :requirements

        sig { returns(Dependabot::RequirementsUpdateStrategy) }
        attr_reader :update_strategy

        sig { returns(T.nilable(Dependabot::Version)) }
        attr_reader :latest_resolvable_version

        sig { void }
        def check_update_strategy
          return if ALLOWED_UPDATE_STRATEGIES.include?(update_strategy)

          raise "Unknown update strategy: #{update_strategy}"
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(req: T::Hash[Symbol, String]).returns(T::Hash[Symbol, String]) }
        def updated_requirement(req)
          req_string = T.must(req[:requirement]).strip
          or_string_reqs = req_string.split(OR_SEPARATOR)
          or_separator = req_string.match(OR_SEPARATOR)&.to_s || " || "
          numeric_or_string_reqs = or_string_reqs
                                   .reject { |r| r.strip.start_with?("dev-") }
          branch_or_string_reqs = or_string_reqs
                                  .select { |r| r.strip.start_with?("dev-") }

          return req unless req_string.match?(/\d/)
          return req if numeric_or_string_reqs.none?
          return updated_alias(req) if req_string.match?(ALIAS_REGEX)
          return req if req_satisfied_by_latest_resolvable?(req_string) &&
                        update_strategy != RequirementsUpdateStrategy::BumpVersions

          new_req =
            case update_strategy
            when RequirementsUpdateStrategy::WidenRanges
              widen_requirement(req, or_separator)
            when RequirementsUpdateStrategy::BumpVersions, RequirementsUpdateStrategy::BumpVersionsIfNecessary
              update_requirement_version(req, or_separator)
            end

          # Add a T.must for new_req as it's defined in the case statement with multiple options
          new_req = T.must(new_req)
          new_req_string =
            [new_req[:requirement], *branch_or_string_reqs].join(or_separator)
          new_req.merge(requirement: new_req_string)
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { params(req: T::Hash[Symbol, String]).returns(T::Hash[Symbol, String]) }
        def updated_alias(req)
          req_string = T.must(req[:requirement])
          parts = req_string.split(/\sas\s/)
          real_version = T.must(parts.first).strip

          # If the version we're aliasing isn't a version then we don't know
          # how to update it, so we just return the existing requirement.
          return req unless version_class.correct?(real_version)

          new_version_string = T.must(latest_resolvable_version).to_s
          new_req = req_string.sub(real_version, new_version_string)
          req.merge(requirement: new_req)
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(req: T::Hash[Symbol, String], or_separator: String).returns(T::Hash[Symbol, String]) }
        def widen_requirement(req, or_separator)
          current_requirement = T.must(req[:requirement])
          reqs = current_requirement.strip.split(SEPARATOR).map(&:strip)

          updated_requirement =
            if reqs.any? { |r| r.strip.start_with?("^") }
              update_caret_requirement(current_requirement, or_separator)
            elsif reqs.any? { |r| r.strip.start_with?("~") }
              update_tilda_requirement(current_requirement, or_separator)
            elsif reqs.any? { |r| r.include?("*") }
              update_wildcard_requirement(current_requirement, or_separator)
            elsif reqs.any? { |r| r.match?(/<|(\s+-\s+)/) }
              update_range_requirement(current_requirement, or_separator)
            else
              update_version_string(current_requirement)
            end

          req.merge(requirement: updated_requirement)
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { params(req: T::Hash[Symbol, String], or_separator: String).returns(T::Hash[Symbol, String]) }
        def update_requirement_version(req, or_separator)
          current_requirement = T.must(req[:requirement])
          reqs = current_requirement.strip.split(SEPARATOR).map(&:strip)

          updated_requirement =
            if reqs.count > 1
              "^#{T.must(latest_resolvable_version)}"
            elsif reqs.any? { |r| r.match?(/<|(\s+-\s+)/) }
              update_range_requirement(current_requirement, or_separator)
            elsif reqs.any? { |r| r.match?(/>[^=]/) }
              current_requirement
            else
              update_version_string(current_requirement)
            end

          req.merge(requirement: updated_requirement)
        end

        sig { params(requirement_string: String).returns(T::Boolean) }
        def req_satisfied_by_latest_resolvable?(requirement_string)
          ruby_requirements(requirement_string)
            .any? { |r| r.satisfied_by?(T.must(latest_resolvable_version)) }
        end

        sig { params(req_string: String).returns(String) }
        def update_version_string(req_string)
          req_string
            .sub(VERSION_REGEX) do |old_version|
              next T.must(latest_resolvable_version).to_s unless req_string.match?(/[~*\^]/)

              old_parts = old_version.split(".")
              new_parts = T.must(latest_resolvable_version).to_s.split(".")
                           .first(old_parts.count)
              new_parts.map.with_index do |part, i|
                old_parts[i] == "*" ? "*" : part
              end.join(".")
            end
        end

        sig { params(requirement_string: String).returns(T::Array[Composer::Requirement]) }
        def ruby_requirements(requirement_string)
          Composer::Requirement.requirements_array(requirement_string)
        end

        sig { params(req_string: String, or_separator: String).returns(String) }
        def update_caret_requirement(req_string, or_separator)
          caret_requirements =
            req_string.split(SEPARATOR).select { |r| r.strip.start_with?("^") }
          version_parts = T.must(latest_resolvable_version).segments

          min_existing_precision =
            caret_requirements.map { |r| r.split(".").count }.min || 0
          first_non_zero_index =
            version_parts.count.times.find { |i| version_parts[i] != 0 } || 0

          precision = [min_existing_precision, first_non_zero_index + 1].max
          version = version_parts.first(precision).map.with_index do |part, i|
            i <= first_non_zero_index ? part : 0
          end.join(".")

          req_string + "#{or_separator}^#{version}"
        end

        sig { params(req_string: String, or_separator: String).returns(String) }
        def update_tilda_requirement(req_string, or_separator)
          tilda_requirements =
            req_string.split(SEPARATOR).select { |r| r.strip.start_with?("~") }
          precision = tilda_requirements.map { |r| r.split(".").count }.min || 0

          version_parts = T.must(latest_resolvable_version).segments.first(precision)
          version_parts[-1] = 0 if version_parts.any?
          version = version_parts.join(".")

          req_string + "#{or_separator}~#{version}"
        end

        sig { params(req_string: String, or_separator: String).returns(String) }
        def update_wildcard_requirement(req_string, or_separator)
          wildcard_requirements =
            req_string.split(SEPARATOR).select { |r| r.include?("*") }
          precision = wildcard_requirements.map do |r|
            r.split(".").reject { |s| s == "*" }.count
          end.min || 0
          wildcard_count = wildcard_requirements.map do |r|
            r.split(".").select { |s| s == "*" }.count
          end.min || 0

          version_parts = T.must(latest_resolvable_version).segments.first(precision)
          version = version_parts.join(".")

          req_string + "#{or_separator}#{version}#{'.*' * wildcard_count}"
        end

        sig { params(req_string: String, or_separator: String).returns(String) }
        def update_range_requirement(req_string, or_separator)
          range_requirements =
            req_string.split(SEPARATOR).select { |r| r.match?(/<|(\s+-\s+)/) }

          if range_requirements.one?
            range_requirement = T.must(range_requirements.first)
            versions = range_requirement.scan(VERSION_REGEX)
            # Convert version strings to Version objects and find the maximum
            upper_bounds = versions.map { |v| version_class.new(T.cast(v, String)) }
            upper_bound = T.cast(upper_bounds.max, Dependabot::Version)
            new_upper_bound = update_greatest_version(
              upper_bound,
              T.must(latest_resolvable_version)
            )

            req_string.sub(upper_bound.to_s, new_upper_bound)
          else
            req_string + "#{or_separator}^#{T.must(latest_resolvable_version)}"
          end
        end

        sig { params(old_version: Dependabot::Version, version_to_be_permitted: Dependabot::Version).returns(String) }
        def update_greatest_version(old_version, version_to_be_permitted)
          version = version_class.new(old_version)
          version = version.release if version.prerelease?

          index_to_update =
            version.segments.map.with_index { |seg, i| seg.to_i.zero? ? 0 : i }.max || 0

          version.segments.map.with_index do |_, index|
            if index < index_to_update
              version_to_be_permitted.segments[index]
            elsif index == index_to_update
              version_to_be_permitted.segments[index].to_i + 1
            else
              0
            end
          end.join(".")
        end

        sig { returns(T.class_of(Dependabot::Composer::Version)) }
        def version_class
          Composer::Version
        end
      end
    end
  end
end
