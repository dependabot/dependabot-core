# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/conda/requirement"
require "dependabot/conda/update_checker"
require "dependabot/conda/version"
require "dependabot/requirements_update_strategy"

module Dependabot
  module Conda
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class RequirementsUpdater
        extend T::Sig

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :requirements

        sig { returns(Dependabot::RequirementsUpdateStrategy) }
        attr_reader :update_strategy

        sig { returns(T.nilable(Dependabot::Conda::Version)) }
        attr_reader :latest_resolvable_version

        sig do
          params(
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            update_strategy: Dependabot::RequirementsUpdateStrategy,
            latest_resolvable_version: T.nilable(String)
          ).void
        end
        def initialize(requirements:, update_strategy:, latest_resolvable_version:)
          @requirements = requirements
          @update_strategy = update_strategy
          @latest_resolvable_version = T.let(
            (Conda::Version.new(latest_resolvable_version) if latest_resolvable_version),
            T.nilable(Dependabot::Conda::Version)
          )
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          return requirements if update_strategy.lockfile_only?
          return requirements unless latest_resolvable_version

          requirements.map do |req|
            case update_strategy
            when RequirementsUpdateStrategy::WidenRanges
              widen_requirement(req)
            when RequirementsUpdateStrategy::BumpVersions
              update_requirement(req)
            when RequirementsUpdateStrategy::BumpVersionsIfNecessary
              update_requirement_if_needed(req)
            else
              raise "Unexpected update strategy: #{update_strategy}"
            end
          end
        end

        private

        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def update_requirement_if_needed(req)
          return req if new_version_satisfies?(req)

          update_requirement(req)
        end

        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def update_requirement(req)
          return req unless req[:requirement]
          return req if ["", "*"].include?(req[:requirement])

          requirement_strings = req[:requirement].split(",").map(&:strip)
          new_req = calculate_updated_requirement(req, requirement_strings)

          new_req == :unfixable ? req.merge(requirement: :unfixable) : req.merge(requirement: new_req)
        end

        sig { params(req: T::Hash[Symbol, T.untyped], requirement_strings: T::Array[String]).returns(T.any(String, Symbol)) }
        def calculate_updated_requirement(req, requirement_strings)
          # Step 1: Check for equality match first (e.g., "==1.21.0" or bare "1.21.0")
          return handle_equality_match(requirement_strings) if equality_match?(requirement_strings)

          # Step 2: Handle range requirements (e.g., ">=3.10,<3.12")
          return handle_range_requirement(req, requirement_strings) if requirement_strings.length > 1

          # Step 3: Handle single constraint (e.g., ">=3.10")
          handle_single_constraint(req)
        end

        sig { params(requirement_strings: T::Array[String]).returns(T::Boolean) }
        def equality_match?(requirement_strings)
          requirement_strings.any? { |r| r.match?(/^[=\d]/) }
        end

        sig { params(requirement_strings: T::Array[String]).returns(T.any(String, Symbol)) }
        def handle_equality_match(requirement_strings)
          find_and_update_equality_match(requirement_strings, latest_resolvable_version)
        end

        sig { params(req: T::Hash[Symbol, T.untyped], requirement_strings: T::Array[String]).returns(T.any(String, Symbol)) }
        def handle_range_requirement(req, requirement_strings)
          # Only skip update if using BumpVersionsIfNecessary strategy and version already satisfies
          # For BumpVersions strategy, always update to the new version
          if update_strategy == RequirementsUpdateStrategy::BumpVersionsIfNecessary &&
             new_version_satisfies?(req)
            return req[:requirement]
          end

          update_requirements_range(requirement_strings)
        end

        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T.any(String, Symbol)) }
        def handle_single_constraint(req)
          # Only skip update if using BumpVersionsIfNecessary strategy and version already satisfies
          # For BumpVersions strategy, always update to the new version
          if update_strategy == RequirementsUpdateStrategy::BumpVersionsIfNecessary &&
             new_version_satisfies?(req)
            return req[:requirement]
          end

          bump_version_string(req[:requirement], T.must(latest_resolvable_version).to_s)
        end

        sig do
          params(
            requirement_strings: T::Array[String],
            latest_version: T.nilable(Conda::Version)
          ).returns(T.any(String, Symbol))
        end
        def find_and_update_equality_match(requirement_strings, latest_version)
          return :unfixable unless latest_version

          current_requirement = requirement_strings.join(",")

          # If dealing with a bare version number, treat it as exact match
          if requirement_strings.length == 1 && T.must(requirement_strings.first).match?(/^\d/)
            return "==#{latest_version}"
          end

          # Find the equality constraint (= or ==)
          equality_req = requirement_strings.find { |r| r.match?(/^=+/) }
          return current_requirement unless equality_req

          # Extract version from equality constraint
          version_string = equality_req.sub(/^=+\s*/, "")

          # Preserve wildcard precision if present
          return preserve_wildcard_precision(equality_req, latest_version.to_s) if version_string.include?("*")

          # Determine operator (= or ==)
          operator = equality_req.match?(/^==/) ? "==" : "="

          # Standard equality update
          "#{operator}#{latest_version}"
        end

        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def widen_requirement(req)
          return req unless req[:requirement]
          return req if ["", "*"].include?(req[:requirement])

          # For WidenRanges, always widen to ensure proper upper bounds
          # Don't return early even if version satisfies - we want to add/update bounds
          new_requirement = widen_requirement_string(req[:requirement])
          req.merge(requirement: new_requirement)
        end

        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
        def new_version_satisfies?(req)
          return false unless req[:requirement]

          Conda::Requirement
            .requirements_array(req[:requirement])
            .all? { |r| r.satisfied_by?(T.must(latest_resolvable_version)) }
        end

        sig { params(req_string: String, new_version: String).returns(T.any(String, Symbol)) }
        def bump_version_string(req_string, new_version)
          # Strip whitespace for matching but preserve operator
          stripped = req_string.strip

          # Parse the current requirement to preserve the operator type
          case stripped
          when /^=\s*([0-9])/
            # Conda exact version: =1.26 or =1.21.*
            if stripped.include?("*")
              # Wildcard: =1.21.* → =2.3.* (preserve wildcard pattern at new major.minor)
              preserve_wildcard_precision(stripped, new_version)
            else
              # Exact: =1.26 → =2.3.4
              "=#{new_version}"
            end
          when /^==\s*([0-9])/
            # Pip exact version: ==1.26 or ==1.21.*
            if stripped.include?("*")
              preserve_wildcard_precision(stripped, new_version)
            else
              "==#{new_version}"
            end
          when /^>=\s*([0-9])/
            # Range constraint: >=1.26 → >=2.3.4
            # Check if version is too high (unfixable)
            current_version_str = stripped[/>=\s*([\d.]+)/, 1]
            if current_version_str && Conda::Version.new(current_version_str) > Conda::Version.new(new_version)
              return :unfixable
            end

            ">=#{new_version}"
          when /^>\s*([0-9])/
            # Greater than: >1.26 → >2.3.4
            ">#{new_version}"
          when /^~=\s*([0-9])/
            # Compatible release: ~=1.26 → ~=2.3.4
            "~=#{new_version}"
          when /^<=/, /^</, /^!=/
            # Upper bound or not-equal constraints: keep unchanged
            req_string
          else
            # Default to conda-style equality
            "=#{new_version}"
          end
        end

        sig { params(req_string: String, new_version: String).returns(String) }
        def preserve_wildcard_precision(req_string, new_version)
          # Count asterisks in original to preserve precision
          # =1.21.* → =2.3.* (preserve major.minor.*)
          # =1.* → =2.* (preserve major.*)

          operator = req_string[/^[=~><!]+/] || "="
          wildcard_parts = req_string.scan(/\d+|\*/)
          new_parts = new_version.split(".")

          # Build new requirement with same wildcard pattern
          result_parts = []
          wildcard_parts.each_with_index do |part, idx|
            if part == "*"
              result_parts << "*"
              break # Stop after first wildcard
            else
              result_parts << (new_parts[idx] || "0")
            end
          end

          "#{operator}#{result_parts.join('.')}"
        end

        sig { params(req_string: String).returns(T.any(String, Symbol)) }
        def widen_requirement_string(req_string)
          # Convert wildcards and exact matches to ranges
          # Order matters: check >= before = to avoid partial matches

          if req_string.include?("*")
            # Wildcard: =1.21.* → >=1.21,<3.0 (widen to major version range)
            convert_wildcard_to_range(req_string)
          elsif req_string.match?(/^>=/)
            # Already a range (>=), update or add upper bound
            result = update_range_upper_bound(req_string)
            return result if result == :unfixable

            result
          elsif req_string.match?(/^(==?)\s*\d/)
            # Exact match: =1.26 or ==1.26 → >=1.26,<3.0
            convert_exact_to_range(req_string)
          elsif req_string.match?(/^~=/)
            # Compatible release: ~=1.3.0 → >=1.3,<3.0
            convert_compatible_to_range(req_string)
          elsif req_string.match?(/^(<=|<|!=)/)
            # Upper bound or not-equal constraints: keep unchanged
            req_string
          else
            # Unknown format, bump version as fallback
            bump_version_string(req_string, T.must(latest_resolvable_version).to_s)
          end
        end

        sig { params(req_string: String).returns(String) }
        def convert_wildcard_to_range(req_string)
          # =1.21.* becomes >=1.21,<3.0 (or whatever major version latest is)
          version_match = req_string.match(/(\d+(?:\.\d+)*)/)
          return req_string unless version_match

          lower_bound = version_match[1]
          new_version = T.must(latest_resolvable_version)
          upper_major = new_version.version_parts[0].to_i + 1

          ">=#{lower_bound},<#{upper_major}.0"
        end

        sig { params(req_string: String).returns(String) }
        def convert_exact_to_range(req_string)
          # =1.26 becomes >=1.26,<3.0
          version_match = req_string.match(/(\d+(?:\.\d+)*)/)
          return req_string unless version_match

          lower_bound = version_match[1]
          new_version = T.must(latest_resolvable_version)
          upper_major = new_version.version_parts[0].to_i + 1

          ">=#{lower_bound},<#{upper_major}.0"
        end

        sig { params(req_string: String).returns(T.any(String, Symbol)) }
        def update_range_upper_bound(req_string)
          # >=1.26,<2.0 becomes >=1.26,<3.0
          # Check if lower bound is too high (unfixable)
          lower_bound_match = req_string.match(/>=\s*([\d.]+)/)
          if lower_bound_match
            lower_version = Conda::Version.new(lower_bound_match[1])
            return :unfixable if lower_version > T.must(latest_resolvable_version)
          end

          new_version = T.must(latest_resolvable_version)
          upper_major = new_version.version_parts[0].to_i + 1

          if req_string.include?(",<")
            # Replace upper bound
            req_string.sub(/,<[\d.]+/, ",<#{upper_major}.0")
          else
            # Add upper bound
            "#{req_string},<#{upper_major}.0"
          end
        end

        sig { params(req_string: String).returns(String) }
        def convert_compatible_to_range(req_string)
          # ~=1.3.0 becomes >=1.3,<3.0
          version_match = req_string.match(/~=\s*([\d.]+)/)
          return req_string unless version_match

          lower_bound = version_match[1]
          # Extract major.minor for lower bound
          parts = T.must(lower_bound).split(".")
          lower_parts = parts.take(2)
          lower_bound_simplified = lower_parts.join(".")

          new_version = T.must(latest_resolvable_version)
          upper_major = new_version.version_parts[0].to_i + 1

          ">=#{lower_bound_simplified},<#{upper_major}.0"
        end

        sig { params(requirement_strings: T::Array[String]).returns(T.any(String, Symbol)) }
        def update_requirements_range(requirement_strings)
          # Handle comma-separated requirements like ">=3.10,<3.12"
          # For BumpVersions strategy (matching Python's logic):
          # - Keep constraints that already satisfy the new version
          # - Update upper bounds (<, <=) that don't satisfy
          # - Lower bounds (>=, >) that don't satisfy are UNFIXABLE

          updated_parts = requirement_strings.map do |req_str|
            stripped = req_str.strip

            # Check if this individual constraint is satisfied by new version
            if Conda::Requirement.requirements_array(stripped).any? { |r| r.satisfied_by?(T.must(latest_resolvable_version)) }
              # Already satisfied - keep unchanged
              stripped
            elsif stripped.match?(/^</)
              # Upper bound not satisfied - update to accommodate new version
              update_upper_bound(stripped)
            elsif stripped.match?(/^>=|^>/)
              # Lower bound not satisfied - this is unfixable for BumpVersions
              # (We don't lower the minimum version requirement)
              return :unfixable
            elsif stripped.match?(/^!=/)
              # Exclusion not satisfied (new version equals excluded version) - unfixable
              return :unfixable
            else
              # Unknown constraint - keep unchanged
              stripped
            end
          end

          updated_parts.join(",")
        end

        sig { params(upper_bound_str: String).returns(String) }
        def update_upper_bound(upper_bound_str)
          # Update upper bound to accommodate new version using Python's algorithm
          new_version = T.must(latest_resolvable_version)

          if upper_bound_str.start_with?("<=")
            # <= constraint: update to new version exactly
            "<=#{new_version}"
          elsif upper_bound_str.start_with?("<")
            # < constraint: calculate appropriate next version
            # Extract current upper bound version
            current_upper = upper_bound_str.sub(/^<\s*/, "")
            updated_version = calculate_next_version_bound(current_upper, new_version)
            "<#{updated_version}"
          else
            # Shouldn't reach here, but return unchanged
            upper_bound_str
          end
        end

        sig { params(current_upper: String, new_version: Conda::Version).returns(String) }
        def calculate_next_version_bound(current_upper, new_version)
          # Python's algorithm: find the rightmost non-zero segment in current upper bound
          # and increment the corresponding segment in the new version
          current_segments = current_upper.split(".").map(&:to_i)
          new_segments = new_version.version_parts.map(&:to_i)

          # Find the index of the rightmost non-zero segment in current upper bound
          index_to_update = current_segments.map.with_index { |n, i| n.to_i.zero? ? 0 : i }.max || 0

          # Ensure we don't go beyond the new version's segment count
          index_to_update = [index_to_update, new_segments.count - 1].min

          # Build new upper bound
          result_segments = new_segments.map.with_index do |_, index|
            if index < index_to_update
              new_segments[index]
            elsif index == index_to_update
              T.must(new_segments[index]) + 1
            else
              0
            end
          end

          result_segments.join(".")
        end
      end
    end
  end
end
