require "spec_helper"
require "tmpdir"
require "bumper/dependency_file"
require "bumper/dependency"
require "bumper/dependency_file_updaters/ruby_dependency_file_updater"

RSpec.describe DependencyFileUpdaters::RubyDependencyFileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: [gemfile, gemfile_lock],
      dependency: dependency
    )
  end
  let(:gemfile) { DependencyFile.new(content: gemfile_body, name: "Gemfile") }
  let(:gemfile_body) { fixture("Gemfile") }
  let(:gemfile_lock) do
    DependencyFile.new(content: fixture("Gemfile.lock"), name: "Gemfile.lock")
  end
  let(:dependency) { Dependency.new(name: "business", version: "1.5.0") }
  let(:tmp_path) { described_class::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    specify { expect { updated_files }.to_not change { Dir.entries(tmp_path) } }
    specify { updated_files.each { |f| expect(f).to be_a(DependencyFile) } }
    its(:length) { is_expected.to eq(2) }

    context "when the old Gemfile specified the version" do
      let(:gemfile_body) { fixture("gemfiles", "version_specified") }

      describe "the updated Gemfile" do
        subject(:file) { updated_files.find { |file| file.name == "Gemfile" } }
        its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
      end

      describe "the updated Gemfile.lock" do
        subject(:file) { updated_files.find { |f| f.name == "Gemfile.lock" } }
        its(:content) { is_expected.to include "business (~> 1.5.0)" }
      end
    end

    context "when the old Gemfile didn't specify the version" do
      let(:gemfile_body) { fixture("gemfiles", "version_not_specified") }

      describe "the updated Gemfile" do
        subject(:file) { updated_files.find { |file| file.name == "Gemfile" } }
        its(:content) { is_expected.to include "\"business\"\n" }
      end

      describe "the updated Gemfile.lock" do
        subject(:file) { updated_files.find { |f| f.name == "Gemfile.lock" } }
        its(:content) { is_expected.to include "business (1.5.0)" }
      end
    end

    context "when the gemfile.lock is missing" do
      subject { -> { updater } }
      let(:updater) do
        described_class.new(dependency_files: [gemfile], dependency: dependency)
      end

      it { is_expected.to raise_error(/No Gemfile.lock/) }
    end
  end
end
