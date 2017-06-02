# frozen_string_literal: true
require "spec_helper"
require "dependabot/file_updaters/base"

RSpec.shared_examples "a dependency file updater" do
  describe "the class" do
    subject { described_class }
    let(:base_class) { Dependabot::FileUpdaters::Base }

    its(:superclass) { is_expected.to eq(base_class) }

    it "implements updated_dependency_files" do
      expect(described_class.public_instance_methods(false)).
        to include(:updated_dependency_files)
    end

    it "implements required_files" do
      expect(described_class.private_instance_methods(false)).
        to include(:required_files)
    end

    it "doesn't define any additional public instance methods" do
      expect(described_class.public_instance_methods).
        to match_array(base_class.public_instance_methods)
    end
  end
end
