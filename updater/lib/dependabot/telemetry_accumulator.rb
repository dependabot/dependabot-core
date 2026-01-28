# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  # TelemetryAccumulator collects telemetry data during a job run
  # so it can be sent in a single API call at job completion.
  # This reduces API calls from N per job to 1 per job.
  class TelemetryAccumulator
    extend T::Sig

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    attr_reader :ecosystem_versions

    sig { returns(T::Array[T.untyped]) }
    attr_reader :ecosystem_meta

    sig { returns(T::Array[T.untyped]) }
    attr_reader :cooldown_meta

    sig { void }
    def initialize
      @ecosystem_versions = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
      @ecosystem_meta = T.let([], T::Array[T.untyped])
      @cooldown_meta = T.let([], T::Array[T.untyped])
      @mutex = T.let(Mutex.new, Mutex)
    end

    sig { params(versions: T::Hash[Symbol, T.untyped]).void }
    def add_ecosystem_versions(versions)
      @mutex.synchronize do
        @ecosystem_versions << versions
      end
    end

    sig { params(meta: T.untyped).void }
    def add_ecosystem_meta(meta)
      return if meta.nil?

      @mutex.synchronize do
        @ecosystem_meta << meta
      end
    end

    sig { params(meta: T.untyped).void }
    def add_cooldown_meta(meta)
      return if meta.nil?

      @mutex.synchronize do
        @cooldown_meta << meta
      end
    end

    sig { returns(T::Boolean) }
    def empty?
      @ecosystem_versions.empty? && @ecosystem_meta.empty? && @cooldown_meta.empty?
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        ecosystem_versions: @ecosystem_versions,
        ecosystem_meta: @ecosystem_meta,
        cooldown_meta: @cooldown_meta
      }
    end
  end
end
