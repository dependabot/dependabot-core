# typed: strict
# frozen_string_literal: true

module StackProf
  # Options used by the spec profiler; its result is discarded.
  sig do
    params(
      mode: Symbol,
      interval: Integer,
      raw: T::Boolean,
      out: String,
      block: T.proc.void
    ).void
  end
  def self.run(mode:, interval:, raw:, out:, &block); end
end
