# frozen_string_literal: true
module Bump
  class DependencyFile
    attr_reader :name, :content

    def initialize(name:, content:)
      @name = name
      @content = content
    end

    def to_h
      { "name" => name, "content" => content }
    end
  end
end
