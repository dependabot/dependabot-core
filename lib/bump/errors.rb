# frozen_string_literal: true

module Bump
  class BumpError < StandardError; end
  class DependencyFileNotFound < BumpError; end
end
