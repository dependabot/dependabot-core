# frozen_string_literal: true

require "dependabot/utils"

module Dependabot
  module GithubActions
    class Version < Gem::Version
    end
  end
end

Dependabot::Utils.
  register_version_class("github_actions", Dependabot::GithubActions::Version)
