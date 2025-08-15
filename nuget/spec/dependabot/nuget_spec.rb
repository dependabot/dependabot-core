# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nuget"
require "dependabot/utils"
require "dependabot/pull_request_creator/labeler"
require "dependabot/dependency"

RSpec.describe Dependabot::Nuget do
  let(:package_manager) { "nuget" }

  describe "registration" do
    it "registers a version class" do
      klass = Dependabot::Utils.version_class_for_package_manager(package_manager)
      expect(klass.ancestors).to include(Gem::Version)
    end

    it "registers a requirement class" do
      klass = Dependabot::Utils.requirement_class_for_package_manager(package_manager)
      expect(klass.ancestors).to include(Gem::Requirement)
    end

    it "registers its label details" do
      expect(
        Dependabot::PullRequestCreator::Labeler
          .label_details_for_package_manager(package_manager)
      ).to be_a(Hash)
    end

    it "registers its production check" do
      expect(
        Dependabot::Dependency.production_check_for_package_manager(package_manager)
      ).to be_a(Proc)
    end
  end
end
