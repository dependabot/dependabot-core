# frozen_string_literal: true
require "spec_helper"
require "bump/update_checkers/base"

RSpec.shared_examples "an update checker" do
  describe "the class" do
    subject { described_class }
    let(:base_class) { Bump::UpdateCheckers::Base }

    its(:superclass) { is_expected.to eq(base_class) }

    it "implements latest_version" do
      expect(described_class.public_instance_methods(false)).
        to include(:latest_version)
    end

    it "doesn't define any additional public instance methods" do
      expect(described_class.public_instance_methods).
        to match_array(base_class.public_instance_methods)
    end
  end
end
