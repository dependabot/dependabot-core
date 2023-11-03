# typed: strong
# frozen_string_literal: true

module Raven
  class << self
    sig { params(_blk: T.proc.params(arg0: Raven::Configuration).void).void }
    def configure(&_blk); end
  end

  class Configuration
    sig { returns(T.nilable(::Logger)) }
    attr_accessor :logger

    sig { returns(T.nilable(String)) }
    attr_accessor :project_root

    sig { returns(T.nilable(::Regexp)) }
    attr_accessor :app_dirs_pattern

    sig { returns(T::Array[T.class_of(Raven::Processor)]) }
    attr_accessor :processors
  end
end
