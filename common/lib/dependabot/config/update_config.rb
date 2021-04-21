# frozen_string_literal: true

module Dependabot
  module Config
    # Configuration for a single ecosystem
    class UpdateConfig
      attr_reader :commit_message_options

      module UpdateType
        IGNORE_PATCH = "patch"
        IGNORE_MINOR = "minor"
        IGNORE_MAJOR = "major"
      end

      def initialize(ignore_conditions: nil, commit_message_options: nil)
        @ignore_conditions = ignore_conditions || []
        @commit_message_options = commit_message_options
      end

      def ignored_versions_for(dep)
        @ignore_conditions.
          select { |ic| ic.dependency_name == dep.name }. # FIXME: wildcard support
          map(&:versions).
          flatten.
          compact
      end

      class IgnoreCondition
        attr_reader :dependency_name
        def initialize(dependency_name:, versions: nil, update_type: nil)
          @dependency_name = dependency_name
          @versions = versions || []
          @update_type = update_type
        end

        def versions(dep)
          versions_by_type(dep) + @versions
        end

        private

        def versions_by_type(dep)
          case @update_type
          when UpdateType::IGNORE_PATCH
            [ignore_version(dep.version, 4)]
          when UpdateType::IGNORE_MINOR
            [ignore_version(dep.version, 3)]
          when UpdateType::IGNORE_MAJOR
            [ignore_version(dep.version, 2)]
          else
            []
          end
        end

        def ignore_version(version, precision)
          parts = version.split(".")
          version_parts = parts.fill(0, parts.length...[3, precision].max).
                          first(precision)

          lower_bound = [
            *version_parts.first(precision - 2),
            "a"
          ].join(".")
          upper_bound = [
            *version_parts.first(precision - 2),
            version_parts[precision - 2].to_i + 1
          ].join(".")

          ">= #{lower_bound}, < #{upper_bound}"
        end
      end

      class CommitMessageOptions
        attr_reader :prefix, :prefix_development, :include

        def initialize(prefix:, prefix_development:, include:)
          @prefix = prefix
          @prefix_development = prefix_development
          @include = include
        end

        def include_scope?
          @include == "scope"
        end

        def to_h
          {
            prefix: @prefix,
            prefix_development: @prefix_development,
            include_scope: include_scope?
          }
        end
      end
    end
  end
end
