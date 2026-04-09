# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel/file_fetcher/bzl_file_fetcher"

RSpec.describe Dependabot::Bazel::FileFetcher::BzlFileFetcher do
  let(:fetcher) { instance_double(Dependabot::Bazel::FileFetcher) }
  let(:module_file) do
    Dependabot::DependencyFile.new(
      name: "MODULE.bazel",
      content: module_content
    )
  end
  let(:module_content) { "" }
  let(:bzl_file_fetcher) do
    described_class.new(module_file: module_file, fetcher: fetcher)
  end

  describe "#fetch_bzl_files" do
    context "with use_extension pointing to a .bzl file" do
      let(:module_content) do
        <<~BAZEL
          bazel_dep(name = "rules_cc", version = "0.1.1")
          my_ext = use_extension("//tools:extensions.bzl", "my_ext")
        BAZEL
      end

      it "fetches the referenced .bzl file" do
        bzl_file = Dependabot::DependencyFile.new(
          name: "tools/extensions.bzl",
          content: ""
        )
        allow(fetcher).to receive(:fetch_file_if_present).with("tools/extensions.bzl").and_return(bzl_file)

        files = bzl_file_fetcher.fetch_bzl_files
        expect(files.map(&:name)).to eq(["tools/extensions.bzl"])
      end
    end

    context "with use_repo_rule pointing to a .bzl file" do
      let(:module_content) do
        <<~BAZEL
          use_repo_rule("//build:repo_rules.bzl", "my_rule")
        BAZEL
      end

      it "fetches the referenced .bzl file" do
        bzl_file = Dependabot::DependencyFile.new(
          name: "build/repo_rules.bzl",
          content: ""
        )
        allow(fetcher).to receive(:fetch_file_if_present).with("build/repo_rules.bzl").and_return(bzl_file)

        files = bzl_file_fetcher.fetch_bzl_files
        expect(files.map(&:name)).to eq(["build/repo_rules.bzl"])
      end
    end

    context "with external repo references" do
      let(:module_content) do
        <<~BAZEL
          my_ext = use_extension("@rules_go//go:extensions.bzl", "go_sdk")
        BAZEL
      end

      it "ignores external repo references" do
        files = bzl_file_fetcher.fetch_bzl_files
        expect(files).to be_empty
      end
    end

    context "with recursive .bzl dependencies via load()" do
      let(:module_content) do
        <<~BAZEL
          my_ext = use_extension("//tools:extensions.bzl", "my_ext")
        BAZEL
      end

      it "follows load() statements recursively" do
        extensions_bzl = Dependabot::DependencyFile.new(
          name: "tools/extensions.bzl",
          content: 'load("//lib:helpers.bzl", "helper_fn")'
        )
        helpers_bzl = Dependabot::DependencyFile.new(
          name: "lib/helpers.bzl",
          content: ""
        )
        allow(fetcher).to receive(:fetch_file_if_present).with("tools/extensions.bzl").and_return(extensions_bzl)
        allow(fetcher).to receive(:fetch_file_if_present).with("lib/helpers.bzl").and_return(helpers_bzl)

        files = bzl_file_fetcher.fetch_bzl_files
        expect(files.map(&:name)).to eq(["tools/extensions.bzl", "lib/helpers.bzl"])
      end
    end

    context "with circular .bzl dependencies" do
      let(:module_content) do
        <<~BAZEL
          my_ext = use_extension("//a:first.bzl", "ext")
        BAZEL
      end

      it "does not loop infinitely" do
        first_bzl = Dependabot::DependencyFile.new(
          name: "a/first.bzl",
          content: 'load("//b:second.bzl", "fn")'
        )
        second_bzl = Dependabot::DependencyFile.new(
          name: "b/second.bzl",
          content: 'load("//a:first.bzl", "fn")'
        )
        allow(fetcher).to receive(:fetch_file_if_present).with("a/first.bzl").and_return(first_bzl)
        allow(fetcher).to receive(:fetch_file_if_present).with("b/second.bzl").and_return(second_bzl)

        files = bzl_file_fetcher.fetch_bzl_files
        expect(files.map(&:name)).to contain_exactly("a/first.bzl", "b/second.bzl")
      end
    end

    context "when a .bzl file cannot be fetched" do
      let(:module_content) do
        <<~BAZEL
          my_ext = use_extension("//tools:missing.bzl", "ext")
        BAZEL
      end

      it "skips missing files" do
        allow(fetcher).to receive(:fetch_file_if_present).with("tools/missing.bzl").and_return(nil)

        files = bzl_file_fetcher.fetch_bzl_files
        expect(files).to be_empty
      end
    end
  end

  describe "extract_bzl_load_dependencies (via fetch_bzl_files)" do
    context "with load() statements" do
      let(:module_content) do
        <<~BAZEL
          my_ext = use_extension("//tools:defs.bzl", "ext")
        BAZEL
      end

      it "extracts workspace-relative load() paths" do
        defs_bzl = Dependabot::DependencyFile.new(
          name: "tools/defs.bzl",
          content: <<~BZL
            load("//lib:utils.bzl", "util_fn")
            load(":local.bzl", "local_fn")
          BZL
        )
        utils_bzl = Dependabot::DependencyFile.new(name: "lib/utils.bzl", content: "")
        local_bzl = Dependabot::DependencyFile.new(name: "tools/local.bzl", content: "")

        allow(fetcher).to receive(:fetch_file_if_present).with("tools/defs.bzl").and_return(defs_bzl)
        allow(fetcher).to receive(:fetch_file_if_present).with("lib/utils.bzl").and_return(utils_bzl)
        allow(fetcher).to receive(:fetch_file_if_present).with("tools/local.bzl").and_return(local_bzl)

        files = bzl_file_fetcher.fetch_bzl_files
        expect(files.map(&:name)).to contain_exactly("tools/defs.bzl", "lib/utils.bzl", "tools/local.bzl")
      end
    end

    context "with Label() references" do
      let(:module_content) do
        <<~BAZEL
          my_ext = use_extension("//java/kotlin-extractor:deps.bzl", "ext")
        BAZEL
      end

      it "does not follow Label() references (regression test for #13718)" do
        deps_bzl = Dependabot::DependencyFile.new(
          name: "java/kotlin-extractor/deps.bzl",
          content: <<~BZL
            load("//lib:utils.bzl", "util_fn")
            src_dir = Label("//java/kotlin-extractor:src")
            template = Label("//tools:template.txt")
          BZL
        )
        utils_bzl = Dependabot::DependencyFile.new(name: "lib/utils.bzl", content: "")

        allow(fetcher).to receive(:fetch_file_if_present).with("java/kotlin-extractor/deps.bzl").and_return(deps_bzl)
        allow(fetcher).to receive(:fetch_file_if_present).with("lib/utils.bzl").and_return(utils_bzl)

        files = bzl_file_fetcher.fetch_bzl_files
        # Should only fetch deps.bzl and the load() target, NOT the Label() targets
        expect(files.map(&:name)).to contain_exactly("java/kotlin-extractor/deps.bzl", "lib/utils.bzl")
      end
    end

    context "with external repo load() statements" do
      let(:module_content) do
        <<~BAZEL
          my_ext = use_extension("//tools:defs.bzl", "ext")
        BAZEL
      end

      it "ignores external repo loads" do
        defs_bzl = Dependabot::DependencyFile.new(
          name: "tools/defs.bzl",
          content: 'load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")'
        )
        allow(fetcher).to receive(:fetch_file_if_present).with("tools/defs.bzl").and_return(defs_bzl)

        files = bzl_file_fetcher.fetch_bzl_files
        # Only the .bzl file itself, no external repo targets
        expect(files.map(&:name)).to eq(["tools/defs.bzl"])
      end
    end
  end

  describe "extract_bzl_file_paths" do
    context "with use_extension referencing non-.bzl paths" do
      let(:module_content) do
        <<~BAZEL
          my_ext = use_extension("//tools:extensions.bzl", "ext")
          another = use_extension("//data:config", "cfg")
        BAZEL
      end

      it "only returns paths ending in .bzl" do
        bzl_file = Dependabot::DependencyFile.new(name: "tools/extensions.bzl", content: "")
        allow(fetcher).to receive(:fetch_file_if_present).with("tools/extensions.bzl").and_return(bzl_file)

        files = bzl_file_fetcher.fetch_bzl_files
        expect(files.map(&:name)).to eq(["tools/extensions.bzl"])
      end
    end
  end
end
