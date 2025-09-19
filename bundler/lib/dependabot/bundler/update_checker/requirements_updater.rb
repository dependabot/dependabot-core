# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/bundler/update_checker"
require "dependabot/requirements_update_strategy"

module Dependabot
  module Bundler
    class UpdateChecker
      class RequirementsUpdater
        extend T::Sig

        class UnfixableRequirement < StandardError; end

        ALLOWED_UPDATE_STRATEGIES = T.let(
          [
            RequirementsUpdateStrategy::LockfileOnly,
            RequirementsUpdateStrategy::BumpVersions,
            RequirementsUpdateStrategy::BumpVersionsIfNecessary
          ].freeze,
          T::Array[Dependabot::RequirementsUpdateStrategy]
        )

        sig do
          params(
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            update_strategy: Dependabot::RequirementsUpdateStrategy,
            updated_source: T.nilable(T::Hash[Symbol, T.untyped]),
            latest_version: T.nilable(String),
            latest_resolvable_version: T.nilable(String)
          ).void
        end
        def initialize(
          requirements:,
          update_strategy:,
          updated_source:,
          latest_version:,
          latest_resolvable_version:
        )
          @requirements = requirements
          @latest_version = T.let(
            (T.cast(Dependabot::Bundler::Version.new(latest_version), Dependabot::Bundler::Version) if latest_version),
            T.nilable(Dependabot::Bundler::Version)
          )
          @updated_source = updated_source
          @update_strategy = update_strategy

          check_update_strategy

          @latest_resolvable_version = T.let(
            if latest_resolvable_version
              T.cast(Dependabot::Bundler::Version.new(latest_resolvable_version), Dependabot::Bundler::Version)
            end,
            T.nilable(Dependabot::Bundler::Version)
          )
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          return requirements if update_strategy.lockfile_only?

          requirements.map do |req|
            if req[:file].include?(".gemspec")
              update_gemspec_requirement(req)
            else
              # If a requirement doesn't come from a gemspec, it must be from
              # a Gemfile.
              update_gemfile_requirement(req)
            end
          end
        end

        private

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :requirements
        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        attr_reader :updated_source
        sig { returns(T.nilable(Dependabot::Bundler::Version)) }
        attr_reader :latest_version
        sig { returns(T.nilable(Dependabot::Bundler::Version)) }
        attr_reader :latest_resolvable_version
        sig { returns(Dependabot::RequirementsUpdateStrategy) }
        attr_reader :update_strategy

        sig { void }
        def check_update_strategy
          return if ALLOWED_UPDATE_STRATEGIES.include?(update_strategy)

          raise "Unknown update strategy: #{update_strategy}"
        end

        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def update_gemfile_requirement(req)
          req = req.merge(source: updated_source)
          return req unless latest_resolvable_version

          case update_strategy
          when RequirementsUpdateStrategy::BumpVersions
            update_version_requirement(req)
          when RequirementsUpdateStrategy::BumpVersionsIfNecessary
            update_version_requirement_if_needed(req)
          else raise "Unexpected update strategy: #{update_strategy}"
          end
        end

        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def update_version_requirement_if_needed(req)
          return req if new_version_satisfies?(req)

          update_version_requirement(req)
        end

        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def update_version_requirement(req)
          requirements =
            req[:requirement].split(",").map { |r| Gem::Requirement.new(r) }

          new_requirement =
            if requirements.any?(&:exact?) then latest_resolvable_version.to_s
            elsif requirements.any? { |r| r.to_s.start_with?("~>") }
              tw_req = requirements.find { |r| r.to_s.start_with?("~>") }
              update_twiddle_version(tw_req, T.must(latest_resolvable_version)).to_s
            else
              update_gemfile_range(requirements).map(&:to_s).join(", ")
            end

          req.merge(requirement: new_requirement)
        end

        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
        def new_version_satisfies?(req)
          return false unless latest_resolvable_version

          Requirement.satisfied_by?(req, T.must(latest_resolvable_version))
        end

        sig { params(requirements: T::Array[Gem::Requirement]).returns(T::Array[Gem::Requirement]) }
        def update_gemfile_range(requirements)
          updated_requirements =
            requirements.flat_map do |r|
              next r if r.satisfied_by?(latest_resolvable_version)

              case op = r.requirements.first.first
              when "<", "<="
                [update_greatest_version(r, T.must(latest_resolvable_version))]
              when "!="
                []
              else
                raise "Unexpected operation for unsatisfied Gemfile " \
                      "requirement: #{op}"
              end
            end

          binding_requirements(updated_requirements)
        end

        sig { params(new_version: Dependabot::Bundler::Version, old_version: Gem::Version).returns(String) }
        def at_same_precision(new_version, old_version)
          release_precision = old_version.to_s.split(".")
                                         .take_while { |i| i.match?(/^\d+$/) }.count
          prerelease_precision =
            old_version.to_s.split(".").count - release_precision

          new_release =
            new_version.to_s.split(".").first(release_precision)
          new_prerelease =
            new_version.to_s.split(".")
                       .drop_while { |i| i.match?(/^\d+$/) }
                       .first([prerelease_precision, 1].max)

          [*new_release, *new_prerelease].join(".")
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def update_gemspec_requirement(req)
          req = req.merge(source: updated_source) if req.fetch(:source)
          return req unless latest_version && latest_resolvable_version

          requirements =
            req[:requirement].split(",").map { |r| Gem::Requirement.new(r) }

          return req if requirements.all? do |r|
            requirement_satisfied?(r, req[:groups])
          end

          updated_requirements =
            requirements.flat_map do |r|
              next r if requirement_satisfied?(r, req[:groups])

              if req[:groups] == ["development"] then bumped_requirements(r)
              else
                widened_requirements(r)
              end
            end

          updated_requirements = binding_requirements(updated_requirements)
          req.merge(requirement: updated_requirements.map(&:to_s).join(", "))
        rescue UnfixableRequirement
          req.merge(requirement: :unfixable)
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { params(req: Gem::Requirement, groups: T::Array[String]).returns(T::Boolean) }
        def requirement_satisfied?(req, groups)
          if groups == ["development"]
            req.satisfied_by?(T.must(latest_resolvable_version))
          else
            req.satisfied_by?(T.must(latest_version))
          end
        end

        sig { params(requirements: T::Array[Gem::Requirement]).returns(T::Array[Gem::Requirement]) }
        def binding_requirements(requirements)
          grouped_by_operator =
            requirements.group_by { |r| r.requirements.first.first }

          binding_reqs = grouped_by_operator.flat_map do |operator, reqs|
            case operator
            when "<", "<=" then reqs.min_by { |r| r.requirements.first.last }
            when ">", ">=" then reqs.max_by { |r| r.requirements.first.last }
            else requirements
            end
          end.compact.uniq

          binding_reqs << Gem::Requirement.new if binding_reqs.empty?
          binding_reqs.sort_by { |r| r.requirements.first.last }
        end

        sig { params(req: Gem::Requirement).returns(T.any(T::Array[Gem::Requirement], Gem::Requirement)) }
        def widened_requirements(req)
          op, version = req.requirements.first

          case op
          when "=", nil
            if version < latest_resolvable_version
              [Gem::Requirement.new("#{op} #{latest_resolvable_version}")]
            else
              req
            end
          when "<", "<=" then [update_greatest_version(req, T.must(latest_version))]
          when "~>" then convert_twiddle_to_range(req, T.must(latest_version))
          when "!=" then []
          when ">", ">=" then raise UnfixableRequirement
          else raise "Unexpected operation for requirement: #{op}"
          end
        end

        sig { params(req: Gem::Requirement).returns(T.any(T::Array[Gem::Requirement], Gem::Requirement)) }
        def bumped_requirements(req)
          op, version = req.requirements.first

          case op
          when "=", nil
            if version < T.must(latest_resolvable_version)
              [Gem::Requirement.new("#{op} #{latest_resolvable_version}")]
            else
              req
            end
          when "~>"
            [update_twiddle_version(req, T.must(latest_resolvable_version))]
          when "<", "<=" then [update_greatest_version(req, T.must(latest_version))]
          when "!=" then []
          when ">", ">=" then raise UnfixableRequirement
          else raise "Unexpected operation for requirement: #{op}"
          end
        end

        # rubocop:disable Metrics/AbcSize
        sig do
          params(
            requirement: Gem::Requirement,
            version_to_be_permitted: Dependabot::Bundler::Version
          )
            .returns(T::Array[Gem::Requirement])
        end
        def convert_twiddle_to_range(requirement, version_to_be_permitted)
          version = requirement.requirements.first.last
          version = version.release if version.prerelease?

          index_to_update = [version.segments.count - 2, 0].max

          ub_segments = version_to_be_permitted.segments.map(&:to_s)
          ub_segments << "0" while ub_segments.count <= index_to_update
          ub_segments = T.must(ub_segments[0..index_to_update])
          ub_segments[index_to_update] = (ub_segments[index_to_update].to_i + 1).to_s

          lb_segments = version.segments.map(&:to_s)
          lb_segments.pop while lb_segments.any? && lb_segments.last == "0"

          return [Gem::Requirement.new("< #{ub_segments.join('.')}")] if lb_segments.none?

          # Ensure versions have the same length as each other (cosmetic)
          length = [lb_segments.count, ub_segments.count].max
          lb_segments.fill("0", lb_segments.count...length)
          ub_segments.fill("0", ub_segments.count...length)

          [
            Gem::Requirement.new(">= #{lb_segments.join('.')}"),
            Gem::Requirement.new("< #{ub_segments.join('.')}")
          ]
        end
        # rubocop:enable Metrics/AbcSize

        # Updates the version in a "~>" constraint to allow the given version
        sig do
          params(
            requirement: Gem::Requirement,
            version_to_be_permitted: Dependabot::Bundler::Version
          ).returns(Gem::Requirement)
        end
        def update_twiddle_version(requirement, version_to_be_permitted)
          old_version = requirement.requirements.first.last
          updated_v = at_same_precision(version_to_be_permitted, old_version)
          Gem::Requirement.new("~> #{updated_v}")
        end

        # Updates the version in a "<" or "<=" constraint to allow the given
        # version
        sig do
          params(
            requirement: Gem::Requirement,
            version_to_be_permitted: Dependabot::Bundler::Version
          ).returns(Gem::Requirement)
        end
        def update_greatest_version(requirement, version_to_be_permitted)
          op, version = requirement.requirements.first
          version = version.release if version.prerelease?

          index_to_update = [
            version.segments.map.with_index { |seg, i| seg.zero? ? 0 : i }.max,
            version_to_be_permitted.segments.count - 1
          ].min

          new_segments = version.segments.map.with_index do |_, index|
            if index < index_to_update
              version_to_be_permitted.segments[index]
            elsif index == index_to_update
              (version_to_be_permitted.segments[index].to_i + 1)
            elsif index > version_to_be_permitted.segments.count - 1
              nil
            else
              0
            end
          end.compact

          Gem::Requirement.new("#{op} #{new_segments.join('.')}")
        end
      end
    end
  end
end
