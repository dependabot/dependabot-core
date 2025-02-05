# typed: strong
# frozen_string_literal: true

module Dependabot
  module Bun
    class Version < Dependabot::Javascript::Version
    end
  end
end

Dependabot::Utils
  .register_version_class("bun", Dependabot::Bun::Version)
