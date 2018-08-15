# frozen_string_literal: true

require "dependabot/update_checkers/python/pip"
require "dependabot/utils/python/version"
require "dependabot/utils/python/requirement"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip
        class RequirementsUpdater
          PYPROJECT_OR_SEPARATOR = /(?<=[a-zA-Z0-9*])\s*\|+/
          PYPROJECT_SEPARATOR = /#{PYPROJECT_OR_SEPARATOR}|,/

          attr_reader :requirements, :update_strategy,
                      :latest_version, :latest_resolvable_version

          def initialize(requirements:, update_strategy:,
                         latest_version:, latest_resolvable_version:)
            @requirements = requirements
            @update_strategy = update_strategy

            if latest_version
              @latest_version = Utils::Python::Version.new(latest_version)
            end

            return unless latest_resolvable_version
            @latest_resolvable_version =
              Utils::Python::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            requirements.map do |req|
              case req[:file]
              when "setup.py" then updated_setup_requirement(req)
              when "pyproject.toml" then updated_pyproject_requirement(req)
              when "Pipfile" then updated_pipfile_requirement(req)
              when /\.txt$|\.in$/ then updated_requirement(req)
              else raise "Unexpected filename: #{req[:file]}"
              end
            end
          end

          private

          def updated_setup_requirement(req)
            return req unless latest_resolvable_version
            return req unless req.fetch(:requirement)
            return req if new_version_satisfies?(req)

            req_strings = req[:requirement].split(",").map(&:strip)

            new_requirement =
              if req_strings.any? { |r| requirement_class.new(r).exact? }
                find_and_update_equality_match(req_strings)
              elsif req_strings.any? { |r| r.start_with?("~=", "==") }
                tw_req = req_strings.find { |r| r.start_with?("~=", "==") }
                convert_to_range(tw_req, latest_resolvable_version)
              else
                update_requirements_range(req_strings)
              end

            req.merge(requirement: new_requirement)
          end

          def updated_pipfile_requirement(req)
            # For now, we just proxy to updated_requirement. In future this
            # method may treat Pipfile requirements differently.
            updated_requirement(req)
          end

          def updated_pyproject_requirement(req)
            return req unless latest_resolvable_version
            return req unless req.fetch(:requirement)

            # If the requirement uses || syntax then we always want to widen it
            if req.fetch(:requirement).match?(PYPROJECT_OR_SEPARATOR)
              return widen_pyproject_requirement(req)
            end

            # If the requirement is a development dependency we always want to
            # bump it
            if req.fetch(:groups).include?("dev-dependencies")
              return update_pyproject_version(req)
            end

            case update_strategy
            when :widen_ranges then widen_pyproject_requirement(req)
            when :bump_versions then update_pyproject_version(req)
            else raise "Unexpected update strategy: #{update_strategy}"
            end
          end

          def update_pyproject_version(req)
            requirement_strings = req[:requirement].split(",").map(&:strip)

            new_requirement =
              if requirement_strings.any? { |r| r.match?(/^==|^\d/) }
                # If there is an equality operator, just update that. It must
                # be binding and any other requirements will be being ignored
                find_and_update_equality_match(requirement_strings)
              elsif requirement_strings.any? { |r| r.start_with?("~", "^") }
                # If a compatibility operator is being used, just bump its
                # version (and remove any other requirements)
                v_req = requirement_strings.find { |r| r.start_with?("~", "^") }
                bump_version(v_req, latest_resolvable_version.to_s)
              elsif new_version_satisfies?(req)
                # Otherwise we're looking at a range operator. No change
                # required if it's already satisfied
                req.fetch(:requirement)
              else
                # But if it's not, update it
                update_requirements_range(requirement_strings)
              end

            req.merge(requirement: new_requirement)
          end

          def widen_pyproject_requirement(req)
            return req if new_version_satisfies?(req)

            new_requirement =
              if req[:requirement].match?(PYPROJECT_OR_SEPARATOR)
                add_new_requirement_option(req[:requirement])
              else
                widen_requirement_range(req[:requirement])
              end

            req.merge(requirement: new_requirement)
          end

          def add_new_requirement_option(req_string)
            option_to_copy = req_string.split(PYPROJECT_OR_SEPARATOR).last.
                             split(PYPROJECT_SEPARATOR).first.strip
            operator       = option_to_copy.gsub(/\d.*/, "").strip

            new_option =
              case operator
              when "", "==", "==="
                find_and_update_equality_match([option_to_copy])
              when "~=", "~", "^"
                bump_version(option_to_copy, latest_resolvable_version.to_s)
              else
                # We don't expect to see OR conditions used with range
                # operators. If / when we see it, we should handle it.
                raise "Unexpected operator: #{operator}"
              end

            # TODO: Match source spacing
            "#{req_string.strip} || #{new_option.strip}"
          end

          def widen_requirement_range(req_string)
            requirement_strings = req_string.split(",").map(&:strip)

            if requirement_strings.any? { |r| r.match?(/(^==|^\d)[^*]*$/) }
              # If there is an equality operator, just update that.
              # (i.e., assume it's being used deliberately)
              find_and_update_equality_match(requirement_strings)
            elsif requirement_strings.any? { |r| r.start_with?("~", "^") } ||
                  requirement_strings.any? { |r| r.include?("*") }
              # If a compatibility operator is being used, widen its
              # range to include the new version
              v_req = requirement_strings.
                      find { |r| r.start_with?("~", "^") || r.include?("*") }
              convert_to_range(v_req, latest_resolvable_version)
            else
              # Otherwise we have a range, and need to update the upper bound
              update_requirements_range(requirement_strings)
            end
          end

          def updated_requirement(req)
            return req unless latest_resolvable_version
            return req unless req.fetch(:requirement)

            requirement_strings = req[:requirement].split(",").map(&:strip)

            new_requirement =
              if requirement_strings.any? { |r| r.start_with?("==") }
                find_and_update_equality_match(requirement_strings)
              elsif requirement_strings.any? { |r| r.start_with?("~=") }
                tw_req = requirement_strings.find { |r| r.start_with?("~=") }
                bump_version(tw_req, latest_resolvable_version.to_s)
              elsif new_version_satisfies?(req)
                req.fetch(:requirement)
              else
                update_requirements_range(requirement_strings)
              end

            req.merge(requirement: new_requirement)
          end

          def new_version_satisfies?(req)
            requirement_class.
              requirements_array(req.fetch(:requirement)).
              any? { |r| r.satisfied_by?(latest_resolvable_version) }
          end

          def find_and_update_equality_match(requirement_strings)
            if requirement_strings.any? { |r| requirement_class.new(r).exact? }
              # True equality match
              requirement_strings.find { |r| requirement_class.new(r).exact? }.
                sub(
                  PythonRequirementParser::VERSION,
                  latest_resolvable_version.to_s
                )
            else
              # Prefix match
              requirement_strings.find { |r| r.match?(/^(=+|\d)/) }.
                sub(PythonRequirementParser::VERSION) do |v|
                  at_same_precision(latest_resolvable_version.to_s, v)
                end
            end
          end

          def at_same_precision(new_version, old_version)
            # return new_version unless old_version.include?("*")

            count = old_version.split(".").count
            precision = old_version.split(".").index("*") || count

            new_version.
              split(".").
              first(count).
              map.with_index { |s, i| i < precision ? s : "*" }.
              join(".")
          end

          def update_requirements_range(requirement_strings)
            ruby_requirements =
              requirement_strings.map { |r| requirement_class.new(r) }

            updated_requirement_strings = ruby_requirements.flat_map do |r|
              next r.to_s if r.satisfied_by?(latest_resolvable_version)

              case op = r.requirements.first.first
              when "<", "<="
                op + update_greatest_version(r.to_s, latest_resolvable_version)
              when "!="
                nil
              else
                raise "Unexpected op for unsatisfied requirement: #{op}"
              end
            end.compact

            updated_requirement_strings.
              sort_by { |r| requirement_class.new(r).requirements.first.last }.
              map(&:to_s).join(",").delete(" ")
          end

          # Updates the version in a constraint to be the given version
          def bump_version(req_string, version_to_be_permitted)
            old_version = req_string.
                          match(/(#{PythonRequirementParser::VERSION})/).
                          captures.first

            req_string.sub(
              old_version,
              at_same_precision(version_to_be_permitted, old_version)
            )
          end

          def convert_to_range(req_string, version_to_be_permitted)
            # Construct an upper bound at the same precision that the original
            # requirement was at (taking into account ~ dynamics)
            index_to_update = index_to_update_for(req_string)
            ub_segments = version_to_be_permitted.segments
            ub_segments << 0 while ub_segments.count <= index_to_update
            ub_segments = ub_segments[0..index_to_update]
            ub_segments[index_to_update] += 1

            lb_segments = lower_bound_segments_for_req(req_string)

            # Ensure versions have the same length as each other (cosmetic)
            length = [lb_segments.count, ub_segments.count].max
            lb_segments.fill(0, lb_segments.count...length)
            ub_segments.fill(0, ub_segments.count...length)

            ">=#{lb_segments.join('.')},<#{ub_segments.join('.')}"
          end

          def lower_bound_segments_for_req(req_string)
            requirement = requirement_class.new(req_string)
            version = requirement.requirements.first.last
            version = version.release if version.prerelease?

            lb_segments = version.segments
            lb_segments.pop while lb_segments.last.zero?

            lb_segments
          end

          def index_to_update_for(req_string)
            req = requirement_class.new(req_string.split(/[.\-]\*/).first)
            version = req.requirements.first.last.release

            if req_string.strip.start_with?("^")
              version.segments.index { |i| i != 0 }
            elsif req_string.include?("*")
              version.segments.count - 1
            elsif req_string.strip.start_with?("~=", "==")
              version.segments.count - 2
            elsif req_string.strip.start_with?("~")
              req_string.split(".").count == 1 ? 0 : 1
            else raise "Don't know how to convert #{req_string} to range"
            end
          end

          # Updates the version in a "<" or "<=" constraint to allow the given
          # version
          def update_greatest_version(req_string, version_to_be_permitted)
            if version_to_be_permitted.is_a?(String)
              version_to_be_permitted =
                Utils::Python::Version.new(version_to_be_permitted)
            end
            version = Utils::Python::Version.new(req_string.gsub(/<=?/, ""))
            version = version.release if version.prerelease?

            index_to_update =
              version.segments.map.with_index { |seg, i| seg.zero? ? 0 : i }.max

            new_segments = version.segments.map.with_index do |_, index|
              if index < index_to_update
                version_to_be_permitted.segments[index]
              elsif index == index_to_update
                version_to_be_permitted.segments[index] + 1
              else 0
              end
            end

            new_segments.join(".")
          end

          def requirement_class
            Utils::Python::Requirement
          end
        end
      end
    end
  end
end
