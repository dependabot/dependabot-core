# frozen_string_literal: true

require "dependabot/workspace/git"

module Dependabot
  module Workspace
    @active_workspace = nil

    class << self
      attr_accessor :active_workspace
    end
  end
end
