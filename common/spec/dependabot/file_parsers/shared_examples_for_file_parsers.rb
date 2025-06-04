# typed: false
# frozen_string_literal: true

require "spec_helper"
require "octokit"
require "dependabot/file_parsers/base"

RSpec.shared_examples "a dependency file parser" do
  describe "the class" do
    subject { described_class }

    let(:base_class) { Dependabot::FileParsers::Base }

    its(:superclass) { is_expected.to be <= base_class }

    it "implements check_required_files" do
      expect(described_class.private_instance_methods(false))
        .to include(:check_required_files)
    end

    it "implements parse" do
      expect(described_class.public_instance_methods)
        .to include(:parse)
    end

    it "doesn't define any additional public instance methods" do
      expect(described_class.public_instance_methods)
        .to match_array(base_class.public_instance_methods)
    end
  end
end
