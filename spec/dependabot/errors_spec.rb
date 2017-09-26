# frozen_string_literal: true

require "spec_helper"
require "dependabot/errors"

RSpec.describe Dependabot::DependencyFileNotFound do
  let(:error) { described_class.new(file_path) }
  let(:file_path) { "path/to/Gemfile" }

  describe "#file_name" do
    subject { error.file_name }
    it { is_expected.to eq("Gemfile") }
  end

  describe "#directory" do
    subject { error.directory }
    it { is_expected.to eq("/path/to") }

    context "with the root directory" do
      let(:file_path) { "Gemfile" }
      it { is_expected.to eq("/") }
    end

    context "with a root level file whose path starts with a slash" do
      let(:file_path) { "/Gemfile" }
      it { is_expected.to eq("/") }
    end

    context "with a nested file whose path starts with a slash" do
      let(:file_path) { "/path/to/Gemfile" }
      it { is_expected.to eq("/path/to") }
    end
  end
end
