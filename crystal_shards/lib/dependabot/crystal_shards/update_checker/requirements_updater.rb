# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/crystal_shards/update_checker"
require "dependabot/crystal_shards/requirement"
require "dependabot/crystal_shards/version"

module Dependabot
  module CrystalShards
    class UpdateChecker
      class RequirementsUpdater
        extend T::Sig

        sig do
          params(
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            target_version: T.nilable(String),
            source: T.nilable(T::Hash[Symbol, T.untyped])
          ).void
        end
        def initialize(requirements:, target_version:, source:)
          @requirements = requirements
          @target_version = target_version
          @source = source
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          requirements.map do |req|
            updated_req = req.dup

            updated_req[:source] = source if source_changed?(req) && source

            if target_version && req[:requirement]
              updated_req[:requirement] = updated_requirement_string(req[:requirement])
            end

            updated_req
          end
        end

        private

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :requirements

        sig { returns(T.nilable(String)) }
        attr_reader :target_version

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        attr_reader :source

        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
        def source_changed?(req)
          src = source
          return false unless src

          req_source = req[:source]
          return true unless req_source.is_a?(Hash)

          src[:ref] != req_source[:ref]
        end

        sig { params(requirement_string: String).returns(String) }
        def updated_requirement_string(requirement_string)
          ver = target_version
          return requirement_string unless ver

          if requirement_string.match?(/^\d/)
            ver
          elsif requirement_string.start_with?("~>")
            "~> #{ver}"
          elsif requirement_string.start_with?(">=")
            ">= #{ver}"
          elsif requirement_string.start_with?("=")
            "= #{ver}"
          else
            requirement_string
          end
        end
      end
    end
  end
end
