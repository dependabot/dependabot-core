# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_updaters/base"

RSpec.shared_examples "a dependency file updater" do
  describe "the class" do
    subject { described_class }
    let(:base_class) { Dependabot::FileUpdaters::Base }

    its(:superclass) { is_expected.to eq(base_class) }

    its(:updated_files_regex) { is_expected.to be_an_instance_of(Array) }

    it "implements updated_dependency_files" do
      expect(described_class.public_instance_methods(false)).
        to include(:updated_dependency_files)
    end

    it "implements check_required_files" do
      expect(described_class.private_instance_methods(false)).
        to include(:check_required_files)
    end

    it "doesn't define any additional public instance methods" do
      expect(described_class.public_instance_methods).
        to match_array(base_class.public_instance_methods)
    end
  end
end
