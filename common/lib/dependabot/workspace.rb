# frozen_string_literal: true

require "dependabot/workspace/git"

module Dependabot
  module Workspace
    @active_workspace = nil

    class << self
      attr_accessor :active_workspace
    end

    def self.setup(repo_contents_path:, directory:)
      Dependabot.logger.debug("Setting up workspace in #{repo_contents_path}")

      @active_workspace = Dependabot::Workspace::Git.new(
        repo_contents_path,
        Pathname.new(directory || "/").cleanpath
      )
    end

    def self.store_change(memo:)
      return unless @active_workspace

      Dependabot.logger.debug("Storing change to workspace: #{memo}")

      @active_workspace.store_change(memo)
    end

    def self.cleanup!
      return unless @active_workspace

      Dependabot.logger.debug("Cleaning up current workspace")

      @active_workspace.reset!
      @active_workspace = nil
    end
  end
end
