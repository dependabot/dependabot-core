# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/dependency_file_updaters/python/pip"
require "bump/shared_helpers"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Bump::DependencyFileUpdaters::Python::Pip do
  it_behaves_like "a dependency file updater"

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
  let(:dependency) do
    Bump::Dependency.new(
      name: "psycopg2",
      version: "2.8.1",
      package_manager: "pip"
    )
  end
  let(:tmp_path) { Bump::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Bump::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated requirements_file" do
      subject(:updated_requirements_file) do
        updated_files.find { |f| f.name == "requirements.txt" }
      end

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
end
