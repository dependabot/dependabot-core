# frozen_string_literal: true

require "spec_helper"
require "dependabot/metadata_finders/base"

RSpec.shared_examples "a dependency metadata finder" do
  describe "the class" do
    subject { described_class }
    let(:base_class) { Dependabot::MetadataFinders::Base }

    its(:superclass) { is_expected.to eq(base_class) }

    it "implements look_up_source" do
      expect(described_class.private_instance_methods(false)).
        to include(:look_up_source)
    end

    it "doesn't define any additional public instance methods" do
      expect(described_class.public_instance_methods).
        to match_array(base_class.public_instance_methods)
    end
  end
end
