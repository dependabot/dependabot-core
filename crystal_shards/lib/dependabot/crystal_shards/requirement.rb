# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/crystal_shards/version"

module Dependabot
  module CrystalShards
    class Requirement < Dependabot::Requirement
      extend T::Sig

      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      sig { params(requirements: T.any(T.nilable(String), T::Array[T.nilable(String)])).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string&.split(",")&.map(&:strip)
        end

        super(requirements)
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("crystal_shards", Dependabot::CrystalShards::Requirement)
