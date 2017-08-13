# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/php/composer"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Php::Composer do
  it_behaves_like "a dependency file parser"

  let(:files) { [composer_json, lockfile] }
  let(:composer_json) do
    Dependabot::DependencyFile.new(
      name: "composer.json",
      content: composer_json_body
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "composer.lock",
      content: lockfile_body
    )
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

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("monolog/monolog") }
        its(:version) { is_expected.to eq("1.0.2") }
      end
    end

    pending "for development dependencies" do
      let(:composer_json_body) do
        fixture("php", "composer_files", "development_dependencies")
      end

      its(:length) { is_expected.to eq(2) }
    end

    context "with the PHP version specified" do
      let(:composer_json_body) do
        fixture("php", "composer_files", "php_specified")
      end
      let(:lockfile_body) { fixture("php", "lockfiles", "php_specified") }

      its(:length) { is_expected.to eq(2) }
    end

    context "with a version with a 'v' prefix" do
      let(:lockfile_body) { fixture("php", "lockfiles", "v_prefix") }

      it "strips the prefix" do
        expect(dependencies.first.version).to eq("1.0.2")
      end
    end

    context "with a non-numeric version" do
      let(:lockfile_body) { fixture("php", "lockfiles", "git_source") }

      it "skips the dependency" do
        expect(dependencies.length).to eq(1)
      end
    end
  end
end
