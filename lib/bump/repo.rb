# frozen_string_literal: true
module Bump
  class Repo
    attr_reader :name, :language, :commit

    def initialize(name:, language:, commit:)
      @name = name
      @language = language
      @commit = commit
    end

    def to_h
      { "name" => name, "language" => language, "commit" => commit }
    end
  end
end
