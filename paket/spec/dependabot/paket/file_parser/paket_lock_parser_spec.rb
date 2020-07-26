# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/paket/file_parser/paket_lockfile_parser"

RSpec.describe Dependabot::Paket::FileParser::PaketLockfileParser do
  subject(:lockfile_parser) do
    described_class.new(dependency_files: dependency_files)
  end
  let(:paket_lock) do
    Dependabot::DependencyFile.new(
      name: "paket.lock",
      content: paket_lock_content
    )
  end
  let(:paket_lock_content) do
    fixture("paket_lock", paket_lockfile_fixture_name)
  end
  let(:paket_lockfile_fixture_name) { "basic.paket.lock" }

  let(:paket_dependencies) do
    Dependabot::DependencyFile.new(
      name: "paket.dependencies",
      content: paket_dependencies_content
    )
  end
  let(:paket_dependencies_content) do
    fixture("paket_dependencies", paket_dependencies_fixture_name)
  end
  let(:paket_dependencies_fixture_name) { "basic.paket.dependencies" }


  describe "#parse" do
    subject(:dependencies) { lockfile_parser.parse }

    context "for paket lockfiles" do
      let(:dependency_files) { [paket_dependencies, paket_lock] }

      its(:length) { is_expected.to eq(13) }

    end

  end

end
