# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bun/file_parser/bun_lock"

module Dependabot
  module Bun
    class FileParser < Dependabot::FileParsers::Base
      class BunLock
        # One entry from the bun.lock "workspaces" object: a root of the dependency graph.
        class Workspace < T::Struct
          # Bun keys packages installed only for a workspace under the workspace's
          # package name (e.g. "app/ms"). The top-level workspace installs into the
          # root, so it has no prefix.
          const :key_prefix, T.nilable(String)
          # Names from dependencies, optionalDependencies and peerDependencies.
          const :production_names, T::Array[String]
          # Names from devDependencies.
          const :development_names, T::Array[String]
        end
      end
    end
  end
end
