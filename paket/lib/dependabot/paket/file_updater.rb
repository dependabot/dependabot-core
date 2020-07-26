# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Paket
    class FileUpdater < Dependabot::FileUpdaters::Base

    end
  end
end

Dependabot::FileUpdaters.register("paket", Dependabot::Paket::FileUpdater)
