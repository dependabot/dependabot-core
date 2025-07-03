# typed: strong
# frozen_string_literal: true

require "nokogiri"
require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"

require "dependabot/rust_toolchain"

module Dependabot
  module RustToolchain
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        Dependabot::Source.from_url(RUST_GITHUB_URL)
      end
    end
  end
end

Dependabot::MetadataFinders.register("rust_toolchain", Dependabot::RustToolchain::MetadataFinder)
