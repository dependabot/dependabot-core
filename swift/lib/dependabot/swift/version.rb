# frozen_string_literal: true

module Dependabot
  module Swift
    class Version < Gem::Version
    end
  end
end

Dependabot::Utils.
  register_version_class("swift", Dependabot::Swift::Version)
