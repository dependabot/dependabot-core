# typed: true
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

      full_path = Pathname.new(File.join(repo_contents_path, directory)).expand_path
      # Handle missing directories by creating an empty one and relying on the
      # file fetcher to raise a DependencyFileNotFound error
      FileUtils.mkdir_p(full_path)

      @active_workspace = Dependabot::Workspace::Git.new(full_path)
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
