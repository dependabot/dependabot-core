# typed: strong
# frozen_string_literal: true

require "fileutils"
require "sorbet-runtime"

require "dependabot/logger"
require "dependabot/shared_helpers"

module Dependabot
  module GithubActions
    module RepositoryCloner
      extend T::Sig

      # Callers only read commits and tags (containing-branch lookup, tag and commit dates), so
      # skip trees and blobs: a full clone of a large repository can fill the disk or time out.
      # Git fetches a missing tree on demand if a later command needs one.
      # Fall back to a full clone if the server or proxy rejects the partial clone, so a lookup
      # never does worse than before.
      sig { params(url: String, path: String, bare: T::Boolean).void }
      def self.clone(url:, path:, bare: false)
        mode = bare ? "--bare" : "--no-checkout"
        SharedHelpers.run_shell_command(
          "git clone #{mode} --filter=tree:0 --no-recurse-submodules #{url} #{path}",
          fingerprint: "git clone #{mode} --filter=tree:0 --no-recurse-submodules <url> <path>"
        )
      rescue SharedHelpers::HelperSubprocessFailed => e
        Dependabot.logger.warn("Partial clone failed, falling back to a full clone: #{e.message.strip}")
        FileUtils.rm_rf(path)
        full_clone_options = bare ? "--bare --no-recurse-submodules" : "--no-recurse-submodules"
        SharedHelpers.run_shell_command(
          "git clone #{full_clone_options} #{url} #{path}",
          fingerprint: "git clone #{full_clone_options} <url> <path>"
        )
      end
    end
  end
end
