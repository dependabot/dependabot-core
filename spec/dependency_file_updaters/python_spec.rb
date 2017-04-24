# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/dependency_file_updaters/python"
require "bump/shared_helpers"

RSpec.describe Bump::DependencyFileUpdaters::Python do
  before { WebMock.disable! }
  after { WebMock.enable! }
  let(:updater) do
    described_class.new(
      dependency_files: [requirements],
      dependency: dependency,
      github_access_token: "token"
    )
  end
  let(:requirements) do
    Bump::DependencyFile.new(
      content: requirements_body,
      name: "requirements.txt"
    )
  end
  let(:requirements_body) do
    fixture("python", "requirements", "version_specified.txt")
  end
  let(:dependency) { Bump::Dependency.new(name: "psycopg2", version: "2.8.1") }
  let(:tmp_path) { Bump::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "new" do
    context "when the requirements.txt is missing" do
      subject { -> { updater } }
      let(:updater) do
        described_class.new(
          dependency_files: [],
          dependency: dependency,
          github_access_token: "token"
        )
      end

      it { is_expected.to raise_error(/No requirements.txt!/) }
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }
    specify { expect { updated_files }.to_not change { Dir.entries(tmp_path) } }
    specify do
      updated_files.each { |f| expect(f).to be_a(Bump::DependencyFile) }
    end
    its(:length) { is_expected.to eq(1) }
  end

  describe "#updated_requirements_file" do
    subject(:updated_requirements_file) { updater.updated_requirements_file }

    its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
    its(:content) { is_expected.to include "luigi==2.2.0\n" }

    context "when only the minor version is specified" do
      let(:requirements_body) do
        fixture("python", "requirements", "minor_version_specified.txt")
      end

      its(:content) { is_expected.to include "psycopg2==2.8\n" }
    end

    context "when there is a comment" do
      let(:requirements_body) do
        fixture("python", "requirements", "comments.txt")
      end
      its(:content) { is_expected.to include "psycopg2==2.8.1  # Comment!\n" }
    end

    context "when there are unused lines" do
      let(:requirements_body) do
        fixture("python", "requirements", "invalid_lines.txt")
      end
      its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
      its(:content) { is_expected.to include "# This is just a comment" }
    end
  end
end
