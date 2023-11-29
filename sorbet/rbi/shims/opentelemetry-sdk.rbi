# typed: strong
# frozen_string_literal: true

module OpenTelemetry
  def self.tracer_provider; end

  module SDK
    def self.configure; end
  end

  module Trace
    def self.current_span; end

    module Status
      sig { params(message: String).void }
      def self.error(message); end
    end

    module Tracer
      def in_span(name, attributes: nil, links: nil, start_timestamp: nil, kind: nil, with_parent: nil,
                  with_parent_context: nil, &block)
      end

      def start_span(name, attributes: nil, links: nil, start_timestamp: nil, kind: nil, with_parent: nil,
                     with_parent_context: nil)
      end

      def finish; end
    end
  end
end
