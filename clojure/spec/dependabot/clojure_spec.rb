# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/clojure"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Clojure do
  it_behaves_like "it registers the required classes", "clojure"

  describe "production check" do
    subject(:production_check) { Dependabot::Dependency.production_check_for_package_manager("clojure") }

    it "treats top-level dependencies as production" do
      expect(production_check.call(%w(dependencies profile:dev))).to be(true)
    end

    it "treats profile, plugin and alias dependencies as development" do
      expect(production_check.call(%w(profile:dev plugins alias:test))).to be(false)
    end
  end
end
