# typed: strong
# frozen_string_literal: true

module Dependabot
  module Javascript
    module Bun
      class Version < Dependabot::Javascript::Version
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("bun", Dependabot::Javascript::Bun::Version)
