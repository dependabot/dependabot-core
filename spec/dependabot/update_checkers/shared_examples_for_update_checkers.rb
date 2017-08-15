# frozen_string_literal: true
require "spec_helper"
require "dependabot/update_checkers/base"

RSpec.shared_examples "an update checker" do
  describe "the class" do
    subject { described_class }
    let(:base_class) { Dependabot::UpdateCheckers::Base }

    its(:superclass) { is_expected.to be <= base_class }

    it "doesn't define any additional public instance methods" do
      expect(described_class.public_instance_methods).
        to match_array(base_class.public_instance_methods)
    end
  end
end
