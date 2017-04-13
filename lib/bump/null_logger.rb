# frozen_string_literal: true
module Bump
  class NullLogger < Logger
    def add(*_args, &_block)
      nil
    end
  end
end
