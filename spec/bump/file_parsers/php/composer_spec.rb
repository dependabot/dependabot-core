# frozen_string_literal: true
require "spec_helper"
require "bump/dependency_file"
require "bump/file_parsers/php/composer"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Bump::FileParsers::Php::Composer do
  it_behaves_like "a dependency file parser"

  let(:files) { [composer_json, lockfile] }
  let(:composer_json) do
    Bump::DependencyFile.new(name: "composer.json", content: composer_json_body)
  end
  let(:lockfile) do
    Bump::DependencyFile.new(name: "composer.lock", content: lockfile_body)
  end
  let(:composer_json_body) do
    fixture("php", "composer_files", "minor_version")
  end
  let(:lockfile_body) do
    fixture("php", "lockfiles", "minor_version")
  end
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    context "with a version specified" do
      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Bump::Dependency) }
        its(:name) { is_expected.to eq("monolog/monolog") }
        its(:version) { is_expected.to eq("1.0.2") }
      end
    end
  end
end
