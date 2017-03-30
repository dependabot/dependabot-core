# frozen_string_literal: true
require "spec_helper"
require "./app/dependency_file"
require "./app/dependency_file_parsers/python"

RSpec.describe DependencyFileParsers::Python do
  let(:files) { [requirements] }
  let(:requirements) do
    DependencyFile.new(name: "requirements.txt", content: requirements_body)
  end
  let(:requirements_body) { fixture("requirements", "requirements.txt") }
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    context "with a version specified" do
      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
      end
    end
  end
end
