# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the project_name fixture defined only in child contexts.

require "spec_helper"
require "dependabot/go_modules/replace_stubber"

RSpec.describe Dependabot::GoModules::ReplaceStubber do
  subject(:stubbed) { stubber.stub_paths(manifest, directory, stub_root: stub_root) }

  let(:stub_root) { File.join(repo_contents_path, "temporary-stubs") }
  let(:stubber) { described_class.new(repo_contents_path) }

  let(:directory) { "/" }
  let(:repo_contents_path) { build_tmp_repo(project_name) }

  let(:manifest) do
    Dir.chdir("#{repo_contents_path}#{directory}") do
      Dependabot::GoModules::GoModManifest.from_json(`go mod edit -json`, file_path: File.join(directory, "go.mod"))
    end
  end

  describe "#with_stubs" do
    let(:project_name) { "replace" }
    let(:checksum) { "h1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" }

    it "retains original checksums alongside new entries when the source graph is incomplete" do
      sum = File.join(repo_contents_path, "go.sum")
      original = "example.com/public v1.9.0 #{checksum}\n"
      added = "example.com/public v1.10.0 #{checksum}\n"
      File.write(sum, original)

      Dir.chdir(repo_contents_path) do
        stubber.with_stubs(on_error: ->(error) { raise error }) do
          File.write(sum, added)
        end
      end

      expect(File.read(sum)).to eq(original + added)
    end

    it "refuses to restore a checksum symlink outside the checkout" do
      Dir.mktmpdir("external-checksums-") do |directory|
        outside = File.join(directory, "go.sum")
        sum = File.join(repo_contents_path, "go.sum")
        File.write(outside, "original\n")
        FileUtils.rm_f(sum)
        File.symlink(outside, sum)

        expect do
          Dir.chdir(repo_contents_path) do
            stubber.with_stubs(on_error: ->(error) { raise error }) { raise "unexpected yield" }
          end
        end.to raise_error(Dependabot::DependencyFileNotResolvable, /outside the checkout/)
        expect(File.read(outside)).to eq("original\n")
      end
    end

    context "without unavailable replacements" do
      let(:project_name) { "monorepo" }

      it "allows tooling to prune checksums from a complete source graph" do
        sum = File.join(repo_contents_path, "go.sum")
        File.write(sum, "example.com/public v1.0.0 #{checksum}\n")

        Dir.chdir(repo_contents_path) do
          stubber.with_stubs(on_error: ->(error) { raise error }) { File.write(sum, "") }
        end

        expect(File.read(sum)).to eq("")
      end
    end
  end

  describe "#stub_paths" do
    context "when replacing a module as child" do
      let(:project_name) { "monorepo" }

      it { is_expected.to eq({}) }
    end

    context "when replacing a module as sibling" do
      let(:project_name) { "monorepo" }
      let(:directory) { "/cmd" }

      it { is_expected.to eq({}) }
    end

    context "when replacing a module outside of checkout" do
      let(:project_name) { "replace" }

      it "provides module-relative paths when no shared root is requested" do
        relative = stubber.stub_paths(manifest, directory)
        expect(relative.keys).to eq(stubbed.keys)
        expect(relative.values).to all(start_with("./"))
      end

      it "places the external target in the supplied temporary root" do
        expect(stubbed.keys).to eq(["../../../../../../foo"])
        expect(File.dirname(stubbed.values.fetch(0))).to eq(stub_root)
      end
    end

    context "when workspace members share an external target" do
      let(:project_name) { "monorepo" }

      def external_manifest(path)
        Dependabot::GoModules::GoModManifest.from_json(
          JSON.generate("Replace" => [{ "Old" => { "Path" => "example.com/shared" }, "New" => { "Path" => path } }]),
          file_path: "go.mod"
        )
      end

      it "uses the same stub across root and nested directories on one instance" do
        root = stubber.stub_paths(external_manifest("../shared"), "/")
        nested = stubber.stub_paths(external_manifest("../../shared"), "/cmd")

        expect(root.values).to eq(nested.values)
      end

      it "preserves an absolute replacement inside the checkout" do
        expect(stubber.stub_paths(external_manifest(File.join(repo_contents_path, "cmd")), "/")).to eq({})
      end

      it "does not confuse a neighboring path with the checkout's prefix" do
        sibling = "#{repo_contents_path}-neighbor"
        Dir.mkdir(sibling)
        begin
          expect(stubber.stub_paths(external_manifest(sibling), "/").keys).to eq([sibling])
        ensure
          Dir.rmdir(sibling)
        end
      end
    end
  end
end
