# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Swift::FileFetcher do
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: [], repo_contents_path: repo_contents_path)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/swift-example",
      directory: directory
    )
  end

  it_behaves_like "a dependency file fetcher"

  context "with Package.swift and Package.resolved" do
    let(:project_name) { "standard" }
    let(:directory) { "/" }

    it "fetches the manifest and resolved files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Package.swift Package.resolved))
    end
  end

  context "with Package.swift only (no Package.resolved)" do
    let(:project_name) { "manifest-only" }
    let(:directory) { "/" }

    it "fetches the manifest and resolved files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Package.swift))
    end
  end

  context "with a directory that doesn't exist" do
    let(:project_name) { "standard" }
    let(:directory) { "/nonexistent" }

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "when enable_swift_xcode_spm experiment is enabled" do
    before { Dependabot::Experiments.register(:enable_swift_xcode_spm, true) }
    after { Dependabot::Experiments.register(:enable_swift_xcode_spm, false) }

    context "with a single .xcodeproj (no Package.swift)" do
      let(:project_name) { "xcode_project" }
      let(:directory) { "/" }

      it "raises a DependencyFileNotFound error because Package.swift is required" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "with multiple .xcodeproj directories" do
      let(:project_name) { "xcode_project_multiple" }
      let(:directory) { "/" }

      it "raises a DependencyFileNotFound error because Package.swift is required" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "with a nested .xcodeproj in a subdirectory" do
      let(:project_name) { "xcode_project_nested" }
      let(:directory) { "/" }

      it "raises a DependencyFileNotFound error because Package.swift is required" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "with both Package.swift and .xcodeproj present" do
      let(:project_name) { "xcode_project_with_manifest" }
      let(:directory) { "/" }

      it "uses the classic SPM flow and ignores the .xcodeproj" do
        files = file_fetcher_instance.files
        names = files.map(&:name)
        expect(names).to match_array(%w(Package.swift Package.resolved))
      end
    end

    context "with .xcodeproj but no Package.resolved inside it" do
      let(:project_name) { "xcode_project_no_resolved" }
      let(:directory) { "/" }

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end

  context "when enable_swift_xcode_spm experiment is disabled" do
    before { Dependabot::Experiments.register(:enable_swift_xcode_spm, false) }

    context "with only .xcodeproj (no Package.swift)" do
      let(:project_name) { "xcode_project" }
      let(:directory) { "/" }

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end
end
