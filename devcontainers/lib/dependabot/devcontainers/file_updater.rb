# typed: strong
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Devcontainers
    class FileUpdater < Dependabot::FileUpdaters::Base
    end
  end
end

Dependabot::FileUpdaters.register("devcontainers", Dependabot::Devcontainers::FileUpdater)
