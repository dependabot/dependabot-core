# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/base"

RSpec.shared_examples "an update checker" do
  describe "the class" do
    subject { described_class }
    let(:base_class) { Dependabot::UpdateCheckers::Base }

    def recent_ancestors
      ancestors = described_class.ancestors.take_while { |a| a != base_class }
      [described_class] + ancestors
    end

    def own_public_methods(include_ancestor_methods)
      (recent_ancestors + [described_class]).
        map { |cls| cls.public_instance_methods(include_ancestor_methods) }.
        flatten.
        uniq
    end

    def own_private_methods(include_ancestor_methods)
      (recent_ancestors + [described_class]).
        map { |cls| cls.private_instance_methods(include_ancestor_methods) }.
        flatten
    end

    it "inherits from the base class" do
      expect(described_class.ancestors).to include(base_class)
    end

    it "implements updated_requirements" do
      expect(own_public_methods(false)).
        to include(:updated_requirements)
    end

    it "implements latest_version" do
      expect(own_public_methods(false)).
        to include(:latest_version)
    end

    it "implements latest_resolvable_version" do
      expect(own_public_methods(false)).
        to include(:latest_resolvable_version)
    end

    it "implements latest_resolvable_version_with_no_unlock" do
      expect(own_public_methods(false)).
        to include(:latest_resolvable_version_with_no_unlock)
    end

    it "implements latest_version_resolvable_with_full_unlock?" do
      expect(own_private_methods(false)).
        to include(:latest_version_resolvable_with_full_unlock?)
    end

    it "implements updated_dependencies_after_full_unlock" do
      expect(own_private_methods(false)).
        to include(:updated_dependencies_after_full_unlock)
    end

    it "doesn't define any additional public instance methods" do
      expect(own_public_methods(true)).
        to match_array(base_class.public_instance_methods(true))
    end
  end
end
