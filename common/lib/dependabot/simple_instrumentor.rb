# frozen_string_literal: true

module Dependabot
  module SimpleInstrumentor
    class << self
      attr_accessor :events, :subscribers

      def subscribe(&block)
        @subscribers ||= []
        @subscribers << block
      end

      def instrument(name, params = {}, &block)
        @subscribers&.each { |s| s.call(name, params) }
        yield if block
      end
    end
  end
end
