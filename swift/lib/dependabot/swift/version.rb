# typed: strong
# frozen_string_literal: true

module Dependabot
  module Swift
    class Version < Dependabot::Version
    end
  end
end

Dependabot::Utils
  .register_version_class("swift", Dependabot::Swift::Version)
