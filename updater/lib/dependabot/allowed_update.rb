# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class AllowedUpdate
    extend T::Sig

    sig { returns(T.nilable(String)) }
    attr_reader :dependency_type

    sig { returns(T.nilable(String)) }
    attr_reader :dependency_name

    sig { returns(T.nilable(String)) }
    attr_reader :update_type

    sig { params(attributes: T::Hash[Symbol, T.untyped]).returns(T::Array[AllowedUpdate]) }
    def self.create_from_job_definition(attributes)
      attributes.fetch(:allowed_updates).map do |allowed_update|
        new(
          dependency_type: allowed_update.fetch("dependency-type", nil),
          dependency_name: allowed_update.fetch("dependency-name", nil),
          update_type: allowed_update.fetch("update-type", nil),
        )
      end
    end

    sig do
      params(
        dependency_type: T.nilable(String),
        dependency_name: T.nilable(String),
        update_type: T.nilable(String)
      ).void
    end
    def initialize(dependency_type:, dependency_name:, update_type:)
      @dependency_type = dependency_type
      @dependency_name = dependency_name
      @update_type = update_type
    end
  end
end
