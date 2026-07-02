# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module GithubActions
    # Integration with the gh-actions-pin lockfile (`.github/workflows/actions.lock`),
    # which is generated and owned by the upstream `gh actions-pin` CLI. This namespace
    # is the boundary: {Lockfile::Reader} parses an existing lock (read-only),
    # {Lockfile::Engine}/{Lockfile::CliEngine} invoke the resolver/rewriter,
    # {Lockfile::Env} builds the subprocess env, {Lockfile::VersionGate} rejects
    # unsupported schema majors.
    module Lockfile
      extend T::Sig
    end
  end
end

require "dependabot/github_actions/lockfile/types"
require "dependabot/github_actions/lockfile/errors"
require "dependabot/github_actions/lockfile/reader"
require "dependabot/github_actions/lockfile/version_gate"
require "dependabot/github_actions/lockfile/env"
require "dependabot/github_actions/lockfile/engine"
require "dependabot/github_actions/lockfile/cli_engine"
