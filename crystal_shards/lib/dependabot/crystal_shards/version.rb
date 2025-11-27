# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module CrystalShards
    class Version < Dependabot::Version
    end
  end
end

Dependabot::Utils.register_version_class("crystal_shards", Dependabot::CrystalShards::Version)
