# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel/file_fetcher"

RSpec.describe Dependabot::Bazel::FileFetcher::BazelrcImportFetcher do
  subject(:fetcher) { described_class.new(fetcher: file_fetcher) }

  let(:file_fetcher) { instance_double(Dependabot::Bazel::FileFetcher) }

  describe "#fetch_bazelrc_imports" do
    context "when .bazelrc is not present" do
      before do
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, ".bazelrc").and_return(nil)
      end

      it "returns empty array" do
        expect(fetcher.fetch_bazelrc_imports).to eq([])
      end
    end

    context "when .bazelrc has no imports" do
      let(:bazelrc_file) do
        Dependabot::DependencyFile.new(
          name: ".bazelrc",
          content: "build --java_runtime_version=remotejdk_11\ntest --test_output=all\n"
        )
      end

      before do
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, ".bazelrc").and_return(bazelrc_file)
      end

      it "returns empty array" do
        expect(fetcher.fetch_bazelrc_imports).to eq([])
      end
    end

    context "when .bazelrc has import with %workspace% prefix" do
      let(:bazelrc_file) do
        Dependabot::DependencyFile.new(
          name: ".bazelrc",
          content: "import %workspace%/tools/preset.bazelrc\nbuild --test_output=all\n"
        )
      end

      let(:imported_file) do
        Dependabot::DependencyFile.new(
          name: "tools/preset.bazelrc",
          content: "build --disk_cache=~/.cache/bazel\n"
        )
      end

      before do
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, ".bazelrc").and_return(bazelrc_file)
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, "tools/preset.bazelrc")
                                             .and_return(imported_file)
      end

      it "fetches the imported file" do
        result = fetcher.fetch_bazelrc_imports
        expect(result.map(&:name)).to eq(["tools/preset.bazelrc"])
      end
    end

    context "when .bazelrc has import without %workspace% prefix" do
      let(:bazelrc_file) do
        Dependabot::DependencyFile.new(
          name: ".bazelrc",
          content: "import tools/preset.bazelrc\n"
        )
      end

      let(:imported_file) do
        Dependabot::DependencyFile.new(
          name: "tools/preset.bazelrc",
          content: "build --disk_cache=~/.cache/bazel\n"
        )
      end

      before do
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, ".bazelrc").and_return(bazelrc_file)
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, "tools/preset.bazelrc")
                                             .and_return(imported_file)
      end

      it "fetches the imported file" do
        result = fetcher.fetch_bazelrc_imports
        expect(result.map(&:name)).to eq(["tools/preset.bazelrc"])
      end
    end

    context "when .bazelrc has try-import" do
      let(:bazelrc_file) do
        Dependabot::DependencyFile.new(
          name: ".bazelrc",
          content: "try-import %workspace%/user.bazelrc\n"
        )
      end

      let(:imported_file) do
        Dependabot::DependencyFile.new(
          name: "user.bazelrc",
          content: "build --config=local\n"
        )
      end

      before do
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, ".bazelrc").and_return(bazelrc_file)
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, "user.bazelrc")
                                             .and_return(imported_file)
      end

      it "fetches the try-imported file" do
        result = fetcher.fetch_bazelrc_imports
        expect(result.map(&:name)).to eq(["user.bazelrc"])
      end
    end

    context "when try-imported file is missing" do
      let(:bazelrc_file) do
        Dependabot::DependencyFile.new(
          name: ".bazelrc",
          content: "try-import %workspace%/user.bazelrc\n"
        )
      end

      before do
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, ".bazelrc").and_return(bazelrc_file)
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, "user.bazelrc").and_return(nil)
        allow(Dependabot.logger).to receive(:warn)
      end

      it "returns empty array and logs a warning" do
        result = fetcher.fetch_bazelrc_imports
        expect(result).to eq([])
        expect(Dependabot.logger).to have_received(:warn).with(
          "Imported bazelrc file 'user.bazelrc' referenced in .bazelrc but not found in repository"
        )
      end
    end

    context "with recursive imports" do
      let(:bazelrc_file) do
        Dependabot::DependencyFile.new(
          name: ".bazelrc",
          content: "import %workspace%/tools/preset.bazelrc\n"
        )
      end

      let(:preset_file) do
        Dependabot::DependencyFile.new(
          name: "tools/preset.bazelrc",
          content: "import %workspace%/tools/ci.bazelrc\nbuild --disk_cache=~/.cache/bazel\n"
        )
      end

      let(:ci_file) do
        Dependabot::DependencyFile.new(
          name: "tools/ci.bazelrc",
          content: "build --remote_cache=grpc://cache.example.com\n"
        )
      end

      before do
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, ".bazelrc").and_return(bazelrc_file)
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, "tools/preset.bazelrc")
                                             .and_return(preset_file)
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, "tools/ci.bazelrc")
                                             .and_return(ci_file)
      end

      it "fetches all transitively imported files" do
        result = fetcher.fetch_bazelrc_imports
        expect(result.map(&:name)).to contain_exactly("tools/preset.bazelrc", "tools/ci.bazelrc")
      end
    end

    context "with circular imports" do
      let(:bazelrc_file) do
        Dependabot::DependencyFile.new(
          name: ".bazelrc",
          content: "import %workspace%/a.bazelrc\n"
        )
      end

      let(:a_file) do
        Dependabot::DependencyFile.new(
          name: "a.bazelrc",
          content: "import %workspace%/b.bazelrc\n"
        )
      end

      let(:b_file) do
        Dependabot::DependencyFile.new(
          name: "b.bazelrc",
          content: "import %workspace%/a.bazelrc\n"
        )
      end

      before do
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, ".bazelrc").and_return(bazelrc_file)
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, "a.bazelrc").and_return(a_file)
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, "b.bazelrc").and_return(b_file)
      end

      it "does not loop infinitely and fetches both files" do
        result = fetcher.fetch_bazelrc_imports
        expect(result.map(&:name)).to contain_exactly("a.bazelrc", "b.bazelrc")
      end
    end

    context "with comments and empty lines in .bazelrc" do
      let(:bazelrc_file) do
        Dependabot::DependencyFile.new(
          name: ".bazelrc",
          content: "# This is a comment\n\nimport %workspace%/tools/preset.bazelrc\n\n" \
                   "# Another comment\nbuild --test_output=all\n"
        )
      end

      let(:imported_file) do
        Dependabot::DependencyFile.new(
          name: "tools/preset.bazelrc",
          content: "build --disk_cache=~/.cache/bazel\n"
        )
      end

      before do
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, ".bazelrc").and_return(bazelrc_file)
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, "tools/preset.bazelrc")
                                             .and_return(imported_file)
      end

      it "correctly parses imports from lines with comments" do
        result = fetcher.fetch_bazelrc_imports
        expect(result.map(&:name)).to eq(["tools/preset.bazelrc"])
      end
    end

    context "with absolute path imports" do
      let(:bazelrc_file) do
        Dependabot::DependencyFile.new(
          name: ".bazelrc",
          content: "import /etc/bazel.bazelrc\nimport %workspace%/tools/preset.bazelrc\n"
        )
      end

      let(:imported_file) do
        Dependabot::DependencyFile.new(
          name: "tools/preset.bazelrc",
          content: "build --disk_cache=~/.cache/bazel\n"
        )
      end

      before do
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, ".bazelrc").and_return(bazelrc_file)
        allow(file_fetcher).to receive(:send).with(:fetch_file_if_present, "tools/preset.bazelrc")
                                             .and_return(imported_file)
      end

      it "skips absolute paths and fetches relative imports" do
        result = fetcher.fetch_bazelrc_imports
        expect(result.map(&:name)).to eq(["tools/preset.bazelrc"])
      end
    end
  end
end
