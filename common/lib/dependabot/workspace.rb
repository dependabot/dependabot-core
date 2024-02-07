# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/workspace/git"

module Dependabot
  module Workspace
    extend T::Sig

    @active_workspace = T.let(nil, T.nilable(Dependabot::Workspace::Git))

    class << self
      extend T::Sig

      sig { returns(T.nilable(Dependabot::Workspace::Git)) }
      attr_accessor :active_workspace
    end

    sig do
      params(
        repo_contents_path: String,
        directory: T.any(Pathname, String)
      ).void
    end
    def self.setup(repo_contents_path:, directory:)
      Dependabot.logger.debug("Setting up workspace in #{repo_contents_path}")

      full_path = Pathname.new(File.join(repo_contents_path, directory)).expand_path
      # Handle missing directories by creating an empty one and relying on the
      # file fetcher to raise a DependencyFileNotFound error
      FileUtils.mkdir_p(full_path)

      @active_workspace = Dependabot::Workspace::Git.new(full_path)
    end

    sig { params(memo: T.nilable(String)).returns(T.nilable(T::Array[Dependabot::Workspace::ChangeAttempt])) }
    def self.store_change(memo:)
      return unless @active_workspace

      Dependabot.logger.debug("Storing change to workspace: #{memo}")

      @active_workspace.store_change(memo)
    end

    sig { void }
    def self.cleanup!
      return unless @active_workspace

      Dependabot.logger.debug("Cleaning up current workspace")

      @active_workspace.reset!
      @active_workspace = nil
    end
  end
end
