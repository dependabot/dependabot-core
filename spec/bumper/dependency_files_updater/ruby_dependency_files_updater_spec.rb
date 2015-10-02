require "spec_helper"
require "tmpdir"
require "bumper/dependency_file"
require "bumper/dependency"
require "bumper/dependency_files_updater/ruby_dependency_files_updater"

RSpec.describe DependencyFilesUpdater::RubyDependencyFilesUpdater do
  let(:updater) { described_class.new(gemfile: gemfile, dependency: dependency) }
  let(:gemfile) { fixture("Gemfile") }
  let(:dependency) { Dependency.new(name: "business", version: "1.5.0") }
  let(:tmp_path) { described_class::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exists?(tmp_path) }
  subject(:updated_files) { updater.updated_dependency_files }

  it "cleans up after updated_files" do
    expect { updated_files }.to_not change { Dir.entries(tmp_path) }
  end

  its(:length) { is_expected.to eq(2) }
  specify { updated_files.each { |file| expect(file).to be_a(DependencyFile) } }

  describe "the Gemfile.lock" do
    subject(:file) { updated_files.find { |file| file.name == "Gemfile.lock" } }

    it { is_expected.to_not be_nil }
    # FIXME: find a way to parse Gemfile.lock and spec the version
    its(:content) { is_expected.to include "1.5.0" }
  end

  describe "the Gemfile" do
    subject(:file) { updated_files.find { |file| file.name == "Gemfile" } }
    its(:content) { is_expected.to include "~> 1.5.0" }

    it "has an updated version" do
      requirement = file.content.match(Gemnasium::Parser::Patterns::GEM_CALL)[5]
      expect(requirement).to include "1.5.0"
    end
  end
end
