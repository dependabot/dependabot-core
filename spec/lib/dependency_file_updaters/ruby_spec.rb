# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/dependency_file_updaters/ruby"

RSpec.describe Bump::DependencyFileUpdaters::Ruby do
  before { WebMock.disable! }
  after { WebMock.enable! }
  let(:updater) do
    described_class.new(
      dependency_files: [gemfile, gemfile_lock],
      dependency: dependency
    )
  end
  let(:gemfile) do
    Bump::DependencyFile.new(content: gemfile_body, name: "Gemfile")
  end
  let(:gemfile_body) { fixture("Gemfile") }
  let(:gemfile_lock) do
    Bump::DependencyFile.new(
      content: fixture("Gemfile.lock"),
      name: "Gemfile.lock"
    )
  end
  let(:dependency) { Bump::Dependency.new(name: "business", version: "1.5.0") }
  let(:tmp_path) { Bump::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "new" do
    context "when the gemfile.lock is missing" do
      subject { -> { updater } }
      let(:updater) do
        described_class.new(dependency_files: [gemfile], dependency: dependency)
      end

      it { is_expected.to raise_error(/No Gemfile.lock/) }
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    specify { expect { updated_files }.to_not change { Dir.entries(tmp_path) } }
    specify do
      updated_files.each { |f| expect(f).to be_a(Bump::DependencyFile) }
    end
    its(:length) { is_expected.to eq(2) }
  end

  describe "#updated_gemfile" do
    subject(:updated_gemfile) { updater.updated_gemfile }

    context "when the full version is specified" do
      let(:gemfile_body) { fixture("gemfiles", "version_specified") }
      its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
      its(:content) { is_expected.to include "\"statesman\", \"~> 1.2.0\"" }
    end

    context "when the minor version is specified" do
      let(:gemfile_body) { fixture("gemfiles", "minor_version_specified") }
      its(:content) { is_expected.to include "\"business\", \"~> 1.5\"" }
      its(:content) { is_expected.to include "\"statesman\", \"~> 1.2\"" }
    end

    context "with a gem whose name includes a number" do
      let(:gemfile_body) { fixture("gemfiles", "gem_with_number") }
      let(:dependency) { Bump::Dependency.new(name: "i18n", version: "1.5.0") }
      its(:content) { is_expected.to include "\"i18n\", \"~> 1.5.0\"" }
    end

    context "when there is a comment" do
      let(:gemfile_body) { fixture("gemfiles", "comments") }
      its(:content) do
        is_expected.to include "\"business\", \"~> 1.5.0\"   # Business time"
      end
    end
  end

  describe "#updated_gemfile_lock" do
    subject(:file) { updater.updated_gemfile_lock }

    context "when the old Gemfile specified the version" do
      let(:gemfile_body) { fixture("gemfiles", "version_specified") }

      it "locks the updated gem to the latest version" do
        expect(file.content).to include "business (1.5.0)"
      end

      it "doesn't change the version of the other (also outdated) gem" do
        expect(file.content).to include "statesman (1.2.1)"
      end
    end

    context "when the old Gemfile didn't specify the version" do
      let(:gemfile_body) { fixture("gemfiles", "version_not_specified") }

      it "locks the updated gem to the latest version" do
        expect(file.content).to include "business (1.8.0)"
      end

      it "doesn't change the version of the other (also outdated) gem" do
        expect(file.content).to include "statesman (1.2.1)"
      end
    end

    context "when the Gem can't be found" do
      let(:gemfile_body) { fixture("gemfiles", "unavailable_gem") }

      it "raises a DependencyFileUpdaters::VersionConflict error" do
        expect { updater.updated_gemfile_lock }.
          to raise_error(Bump::SharedHelpers::ChildProcessFailed)
      end
    end

    context "when there is a version conflict" do
      let(:gemfile_body) { fixture("gemfiles", "version_conflict") }
      let(:dependency) do
        Bump::Dependency.new(name: "ibandit", version: "0.8.5")
      end

      it "raises a DependencyFileUpdaters::VersionConflict error" do
        expect { updater.updated_gemfile_lock }.
          to raise_error(Bump::DependencyFileUpdaters::VersionConflict)
      end
    end
  end
end
