require 'pp'

module Workers
  class TestConsumer
    include Hutch::Consumer
    consume 'bump.test'

    def process(message)
      pp message
      pp message["this"]
      pp message[:this]
    end
  end
end
