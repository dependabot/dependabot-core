# frozen_string_literal: true
module Bump
  class Dependency
    attr_reader :name, :version, :previous_version, :language

    def initialize(name:, version:, previous_version: nil, language: nil)
      @name = name
      @version = version
      @previous_version = previous_version
      @language = language
    end

    def to_h
      {
        "name" => name,
        "version" => version,
        "previous_version" => previous_version,
        "language" => language
      }
    end
  end
end
