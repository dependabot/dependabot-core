# frozen_string_literal: true
require "spec_helper"
require "./app/dependency"
require "./app/dependency_file"
require "./app/dependency_file_updaters/python"

RSpec.describe DependencyFileUpdaters::Python do
  before { WebMock.disable! }
  after { WebMock.enable! }
  let(:updater) do
    described_class.new(
      dependency_files: [requirements],
      dependency: dependency
    )
  end
  let(:requirements) do
    DependencyFile.new(content: requirements_body, name: "requirements.txt")
  end
  let(:requirements_body) { fixture("requirements", "requirements.txt") }
  let(:dependency) { Dependency.new(name: "psycopg2", version: "2.6.1") }
  let(:tmp_path) { SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "new" do
    context "when the requirements.txt is missing" do
      subject { -> { updater } }
      let(:updater) do
        described_class.new(dependency_files: [], dependency: dependency)
      end

      it { is_expected.to raise_error(/No requirements.txt!/) }
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }
    specify { expect { updated_files }.to_not change { Dir.entries(tmp_path) } }
    specify { updated_files.each { |f| expect(f).to be_a(DependencyFile) } }
    its(:length) { is_expected.to eq(1) }
  end

  describe "#updated_requirements_file" do
    subject(:updated_requirements_file) { updater.updated_requirements_file }

    its(:content) { is_expected.to include "psycopg2==2.6.1" }
    its(:content) { is_expected.to include "luigi==2.2.0" }

    context "when only the minor version is specified" do
      let(:dependency) do
        Dependency.new(name: "psycopg2", version: "2.6.1")
      end
      let(:requirements_body) do
        fixture("requirements", "requirements-minor-specified.txt")
      end

      its(:content) { is_expected.to include "psycopg2==2.6" }
    end
  end
end
