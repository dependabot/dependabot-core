# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/metadata_finders/base"

RSpec.shared_examples "a dependency metadata finder" do
  describe "the class" do
    subject { described_class }

    let(:base_class) { Dependabot::MetadataFinders::Base }

    it "inherits from MetadataFinders::Base" do
      expect(described_class.ancestors).to include(base_class)
    end

    it "implements look_up_source" do
      expect(described_class.private_method_defined?(:look_up_source))
        .to be true
    end

    it "doesn't define any additional public instance methods" do
      expect(described_class.public_instance_methods)
        .to match_array(base_class.public_instance_methods)
    end
  end
end
