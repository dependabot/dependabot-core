# typed: strict
# frozen_string_literal: true

module RSpec
  module Core
    class ExampleGroup
      include ::WebMock::API
      include ::WebMock::Matchers
    end
  end
end
