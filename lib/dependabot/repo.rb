# frozen_string_literal: true
module Dependabot
  class Repo
    attr_reader :name, :package_manager, :commit

    def initialize(name:, commit:)
      @name = name
      @commit = commit
    end

    def to_h
      {
        "name" => name,
        "commit" => commit
      }
    end
  end
end
