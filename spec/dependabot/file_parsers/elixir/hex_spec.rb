# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/elixir/hex"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Elixir::Hex do
  it_behaves_like "a dependency file parser"

  let(:files) { [mixfile, lockfile] }
  let(:mixfile) do
    Dependabot::DependencyFile.new(name: "mix.exs", content: mixfile_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "mix.lock", content: lockfile_body)
  end
  let(:mixfile_body) do
    fixture("elixir", "mixfiles", "minor_version_specified")
  end
  let(:lockfile_body) do
    fixture("elixir", "lockfiles", "minor_version_specified")
  end
  let(:parser) { described_class.new(dependency_files: files, repo: "org/nm") }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(6) }

    context "with a version specified" do
      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("phoenix_live_reload") }
        its(:version) { is_expected.to eq("1.0.8") }
      end
    end
  end
end
