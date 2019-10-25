# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/puppet/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Puppet::FileParser do
  it_behaves_like "a dependency file parser"

  let(:repo) { "jpogran/control-repo" }
  let(:branch) { "production" }
  let(:directory) { "/" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: repo,
      directory: directory,
      branch: branch
    )
  end

  let(:puppet_file_fixture_name) { "Puppetfile" }
  let(:puppet_file_content) { fixture("puppet", puppet_file_fixture_name) }
  let(:puppet_file) do
    Dependabot::DependencyFile.new(
      name: "Puppetfile",
      content: puppet_file_content
    )
  end
  let(:files) { [puppet_file] }
  let(:parser) { described_class.new(dependency_files: files, source: source) }

  it "requires a Puppetfile to be present" do
    expect do
      described_class.new(dependency_files: [], source: source)
    end.to raise_error(RuntimeError)
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    describe "top level dependencies" do
      subject(:dependencies) do
        parser.parse.select(&:top_level?)
      end

      its(:length) { is_expected.to eq(2) }

      describe "a dependency in a Puppetfile" do
        subject(:dependency) do
          dependencies.find { |d| d.name == "puppetlabs-dsc" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("puppetlabs-dsc")
          expect(dependency.version).to eq("1.4.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.4.0",
              file: "Puppetfile",
              groups: [],
              source: {
                type: "default",
                source: "puppetlabs/dsc"
              }
            }]
          )
        end
      end
    end
  end
end
