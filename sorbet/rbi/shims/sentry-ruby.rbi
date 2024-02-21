# typed: strong
# frozen_string_literal: true

module Sentry
  sig { params(_blk: T.proc.params(arg0: Sentry::Configuration).void).void }
  def init&_blk); end

  class Configuration
    sig { returns(T.nilable(String)) }
    attr_accessor :release

    sig { returns(T.nilable(::Logger)) }
    attr_accessor :logger

    sig { returns(T.nilable(String)) }
    attr_accessor :project_root

    sig { returns(T.nilable(::Regexp)) }
    attr_accessor :app_dirs_pattern

    sig { returns(T::Array[T.class_of(Sentry::Processor)]) }
    attr_accessor :processors
  end
end
