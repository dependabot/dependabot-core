# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/hex/version"
require "dependabot/hex/requirement"
require "dependabot/hex/update_checker"

module Dependabot
  module Hex
    class UpdateChecker
      class RequirementsUpdater
        extend T::Sig

        OPERATORS = />=|<=|>|<|==|~>/
        AND_SEPARATOR = /\s+and\s+/
        OR_SEPARATOR = /\s+or\s+/
        SEPARATOR = /#{AND_SEPARATOR}|#{OR_SEPARATOR}/

        sig do
          params(
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            latest_resolvable_version: T.nilable(String),
            updated_source: T.nilable(T::Hash[Symbol, T.nilable(String)])
          ).void
        end
        def initialize(
          requirements:,
          latest_resolvable_version:,
          updated_source:
        )
          @requirements = T.let(requirements, T::Array[T::Hash[Symbol, T.untyped]])
          @updated_source = T.let(updated_source, T.nilable(T::Hash[Symbol, T.nilable(String)]))
          @latest_resolvable_version = T.let(nil, T.nilable(Dependabot::Version))

          return unless latest_resolvable_version
          return unless Hex::Version.correct?(latest_resolvable_version)

          @latest_resolvable_version = Hex::Version.new(latest_resolvable_version)
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          requirements.map { |req| updated_mixfile_requirement(req) }
        end

        private

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :requirements

        sig { returns(T.nilable(Dependabot::Version)) }
        attr_reader :latest_resolvable_version

        sig { returns(T.nilable(T::Hash[Symbol, T.nilable(String)])) }
        attr_reader :updated_source

        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/AbcSize
        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def updated_mixfile_requirement(req)
          req = update_source(req)
          return req unless latest_resolvable_version && req[:requirement]
          return req if req_satisfied_by_latest_resolvable?(req[:requirement])

          or_string_reqs = req[:requirement].split(OR_SEPARATOR)
          last_string_reqs = or_string_reqs.last.split(AND_SEPARATOR)
                                           .map(&:strip)

          new_requirement =
            if last_string_reqs.any? { |r| r.match(/^(?:\d|=)/) }
              exact_req = last_string_reqs.find { |r| r.match(/^(?:\d|=)/) }
              update_exact_version(exact_req, T.must(latest_resolvable_version)).to_s
            elsif last_string_reqs.any? { |r| r.start_with?("~>") }
              tw_req = last_string_reqs.find { |r| r.start_with?("~>") }
              update_twiddle_version(tw_req, T.must(latest_resolvable_version)).to_s
            else
              update_mixfile_range(last_string_reqs).map(&:to_s).join(" and ")
            end

          new_requirement = req[:requirement] + " or " + new_requirement if or_string_reqs.count > 1

          req.merge(requirement: new_requirement)
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity

        sig { params(requirement_hash: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def update_source(requirement_hash)
          # Only git sources ever need to be updated. Anything else should be
          # left alone.
          return requirement_hash unless requirement_hash.dig(:source, :type) == "git"

          requirement_hash.merge(source: updated_source)
        end

        sig { params(requirement_string: String).returns(T::Boolean) }
        def req_satisfied_by_latest_resolvable?(requirement_string)
          ruby_requirements(requirement_string)
            .any? { |r| r.satisfied_by?(T.must(latest_resolvable_version)) }
        end

        sig { params(requirement_string: String).returns(T::Array[Hex::Requirement]) }
        def ruby_requirements(requirement_string)
          requirement_class.requirements_array(requirement_string)
        end

        sig { params(previous_req: String, new_version: Dependabot::Version).returns(String) }
        def update_exact_version(previous_req, new_version)
          op = previous_req.match(OPERATORS).to_s
          old_version =
            Hex::Version.new(previous_req.gsub(OPERATORS, ""))
          updated_version = at_same_precision(new_version, old_version)
          "#{op} #{updated_version}".strip
        end

        sig { params(previous_req: String, new_version: Dependabot::Version).returns(Hex::Requirement) }
        def update_twiddle_version(previous_req, new_version)
          previous_req = requirement_class.new(previous_req)
          old_version = previous_req.requirements.first.last
          updated_version = at_same_precision(new_version, old_version)
          requirement_class.new("~> #{updated_version}")
        end

        sig { params(requirements: T::Array[String]).returns(T::Array[Hex::Requirement]) }
        def update_mixfile_range(requirements)
          requirements = requirements.map { |r| requirement_class.new(r) }
          updated_requirements =
            requirements.flat_map do |r|
              next r if r.satisfied_by?(T.must(latest_resolvable_version))

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

        sig { params(new_version: Dependabot::Version, old_version: Dependabot::Version).returns(String) }
        def at_same_precision(new_version, old_version)
          precision = old_version.to_s.split(".").count
          new_version.to_s.split(".").first(precision).join(".")
        end

        # Updates the version in a "<" or "<=" constraint to allow the given
        # version
        sig do
          params(requirement: Hex::Requirement, version_to_be_permitted: Dependabot::Version).returns(Hex::Requirement)
        end
        def update_greatest_version(requirement, version_to_be_permitted)
          op, version = requirement.requirements.first
          version = version.release if version.prerelease?

          index_to_update =
            version.segments.map.with_index { |seg, i| seg.zero? ? 0 : i }.max

          new_segments = version.segments.map.with_index do |_, index|
            if index < index_to_update
              version_to_be_permitted.segments[index]
            elsif index == index_to_update
              version_to_be_permitted.segments[index].to_i + 1
            else
              0
            end
          end

          requirement_class.new("#{op} #{new_segments.join('.')}")
        end

        sig { params(requirements: T::Array[Hex::Requirement]).returns(T::Array[Hex::Requirement]) }
        def binding_requirements(requirements)
          grouped_by_operator =
            requirements.group_by { |r| r.requirements.first.first }

          binding_reqs = grouped_by_operator.flat_map do |operator, reqs|
            case operator
            when "<", "<="
              min_req = reqs.min_by { |r| r.requirements.first.last }
              min_req ? [min_req] : []
            when ">", ">="
              max_req = reqs.max_by { |r| r.requirements.first.last }
              max_req ? [max_req] : []
            else
              requirements
            end
          end.uniq.compact

          binding_reqs << requirement_class.new if binding_reqs.empty?
          binding_reqs.sort_by { |r| r.requirements.first.last }
        end

        sig { returns(T.class_of(Hex::Requirement)) }
        def requirement_class
          Hex::Requirement
        end
      end
    end
  end
end
