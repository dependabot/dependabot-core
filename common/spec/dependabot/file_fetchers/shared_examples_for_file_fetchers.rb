# frozen_string_literal: true

require "spec_helper"
require "octokit"
require "dependabot/file_fetchers/base"

RSpec.shared_examples "a dependency file fetcher" do
  describe "the class" do
    subject { described_class }
    let(:base_class) { Dependabot::FileFetchers::Base }

    its(:superclass) { is_expected.to eq(base_class) }

    it "implements required_files_in?" do
      expect(described_class.public_methods(false)).
        to include(:required_files_in?)
    end

    it "implements required_files_message" do
      expect(described_class.public_methods(false)).
        to include(:required_files_message)
    end

    it "implements fetch_files" do
      expect(described_class.private_instance_methods(false)).
        to include(:fetch_files)
    end

    it "doesn't define any additional public instance methods" do
      expect(described_class.public_instance_methods).
        to match_array(base_class.public_instance_methods)
    end
  end
end
