# typed: false
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "dependabot/dependency_file"
require "dependabot/git_attributes"

RSpec.describe Dependabot::GitAttributes do
  describe ".reconcile_line_endings!" do
    let(:repo) { write_tmp_repo(attribute_files) }

    after { FileUtils.remove_entry(repo) }

    def dep_file(name:, content:, directory: "/")
      Dependabot::DependencyFile.new(name: name, content: content, directory: directory)
    end

    def reconcile(updated, original: [], path: repo)
      described_class.reconcile_line_endings!(updated, original_files: original, repo_contents_path: path)
    end

    context "with an attributes file declaring text/binary rules" do
      let(:attribute_files) do
        [
          dep_file(name: ".gitattributes", content: <<~ATTRS),
            * text=auto
            *.bat text eol=crlf
            *.ps1 eol=crlf
            *.jar binary
            vendor/** -text
          ATTRS
          dep_file(name: "sub/.gitattributes", content: "*.md text eol=lf\n")
        ]
      end

      it "stores an eol=crlf file (gradlew.bat) as LF, the git index form" do
        file = dep_file(name: "gradlew.bat", content: "@echo\r\noff\r\n")
        reconcile([file])
        expect(file.content).to eq("@echo\noff\n")
      end

      it "leaves binary files untouched" do
        file = dep_file(name: "lib.jar", content: "a\r\nb\r\n")
        reconcile([file])
        expect(file.content).to eq("a\r\nb\r\n")
      end

      it "leaves -text files untouched even when a broader text=auto matches" do
        file = dep_file(name: "blob.dat", content: "a\r\nb\r\n", directory: "/vendor")
        reconcile([file])
        expect(file.content).to eq("a\r\nb\r\n")
      end

      it "honors a nested .gitattributes rule" do
        file = dep_file(name: "readme.md", content: "x\r\ny\r\n", directory: "/sub")
        reconcile([file])
        expect(file.content).to eq("x\ny\n")
      end

      it "normalizes text=auto content that looks textual" do
        file = dep_file(name: "notes.txt", content: "one\r\ntwo\r\n")
        reconcile([file])
        expect(file.content).to eq("one\ntwo\n")
      end

      # git itself would skip conversion here (blob history is CRLF); we
      # renormalize deliberately so the file converges on the declared attribute.
      it "renormalizes text=auto content to LF even when the original was committed CRLF" do
        original = dep_file(name: "notes.txt", content: "one\r\ntwo\r\n")
        updated = dep_file(name: "notes.txt", content: "one\r\ntwo\r\nthree\r\n")
        reconcile([updated], original: [original])
        expect(updated.content).to eq("one\ntwo\nthree\n")
      end

      it "leaves text=auto content that contains NUL bytes untouched" do
        file = dep_file(name: "weird.dat", content: "a\x00b\r\n")
        reconcile([file])
        expect(file.content).to eq("a\x00b\r\n")
      end

      it "leaves text=auto content with NUL bytes untouched even when an original exists" do
        original = dep_file(name: "weird.dat", content: "a\r\nb\r\n")
        updated = dep_file(name: "weird.dat", content: "a\x00b\nc\n")
        reconcile([updated], original: [original])
        expect(updated.content).to eq("a\x00b\nc\n")
      end

      it "leaves NUL-byte content under text=auto eol=crlf untouched, matching git" do
        file = dep_file(name: "run.ps1", content: "a\x00b\r\nc\r\n")
        reconcile([file])
        expect(file.content).to eq("a\x00b\r\nc\r\n")
      end

      it "stores textual content under text=auto eol=crlf as LF" do
        file = dep_file(name: "run.ps1", content: "a\r\nb\r\n")
        reconcile([file])
        expect(file.content).to eq("a\nb\n")
      end

      it "leaves text=auto content with a lone CR untouched, matching git" do
        file = dep_file(name: "notes.txt", content: "a\rb\r\nc\r\n")
        reconcile([file])
        expect(file.content).to eq("a\rb\r\nc\r\n")
      end

      it "leaves text=auto content that is mostly non-printable untouched" do
        file = dep_file(name: "notes.txt", content: "#{1.chr * 200}\r\n")
        reconcile([file])
        expect(file.content).to eq("#{1.chr * 200}\r\n")
      end

      it "matches the original endings of textual -text files to avoid noisy diffs" do
        original = dep_file(name: "blob.dat", content: "a\r\nb\r\n", directory: "/vendor")
        updated = dep_file(name: "blob.dat", content: "a\nb\nc\n", directory: "/vendor")
        reconcile([updated], original: [original])
        expect(updated.content).to eq("a\r\nb\r\nc\r\n")
      end

      # The dependabot/dependabot-core#8693 scenario: the updater rewrites only
      # the lines it touches with LF, leaving a CRLF -text file with mixed endings.
      it "restores uniform endings when the updater mixed LF into a CRLF -text file" do
        original = dep_file(name: "nightly.yaml", content: "uses: a@v1\r\nname: x\r\n", directory: "/vendor")
        updated = dep_file(name: "nightly.yaml", content: "uses: a@v2\nname: x\r\n", directory: "/vendor")
        reconcile([updated], original: [original])
        expect(updated.content).to eq("uses: a@v2\r\nname: x\r\n")
      end
    end

    context "with more path bytes than fit one command line" do
      let(:attribute_files) { [dep_file(name: ".gitattributes", content: "*.bat text eol=crlf\n")] }

      it "reconciles every file" do
        long_dir = "vendored/#{'d' * 200}"
        files = Array.new(1000) do |i|
          dep_file(name: "#{long_dir}/f#{i}.bat", content: "a\r\nb\r\n")
        end
        reconcile(files)
        expect(files.first.content).to eq("a\nb\n")
        expect(files.last.content).to eq("a\nb\n")
      end
    end

    context "with a bare eol rule and no text attribute" do
      let(:attribute_files) { [dep_file(name: ".gitattributes", content: "*.ps1 eol=crlf\n")] }

      it "normalizes NUL-byte content, since a bare eol implicitly sets text" do
        file = dep_file(name: "run.ps1", content: "a\x00b\r\nc\r\n")
        reconcile([file])
        expect(file.content).to eq("a\x00b\nc\n")
      end

      it "stores textual content as LF" do
        file = dep_file(name: "run.ps1", content: "a\r\nb\r\n")
        reconcile([file])
        expect(file.content).to eq("a\nb\n")
      end
    end

    context "when no attribute governs the file" do
      let(:attribute_files) { [dep_file(name: ".gitattributes", content: "*.bat text eol=crlf\n")] }

      it "matches the original file's line endings to avoid noisy diffs" do
        original = dep_file(name: "config.yml", content: "a\r\nb\r\n")
        updated = dep_file(name: "config.yml", content: "a\nb\nc\n")
        reconcile([updated], original: [original])
        expect(updated.content).to eq("a\r\nb\r\nc\r\n")
      end

      it "leaves a newly-created file as produced" do
        updated = dep_file(name: "new.yml", content: "a\nb\n")
        reconcile([updated], original: [])
        expect(updated.content).to eq("a\nb\n")
      end

      it "leaves the update untouched when the original has mixed endings" do
        original = dep_file(name: "config.yml", content: "a\r\nb\n")
        updated = dep_file(name: "config.yml", content: "a\nb\nc\n")
        reconcile([updated], original: [original])
        expect(updated.content).to eq("a\nb\nc\n")
      end
    end

    context "when no clone is available" do
      let(:repo) { Dir.mktmpdir }

      it "is a no-op when repo_contents_path is nil" do
        file = dep_file(name: "gradlew.bat", content: "@echo\r\noff\r\n")
        reconcile([file], path: nil)
        expect(file.content).to eq("@echo\r\noff\r\n")
      end

      it "is a no-op when the path is not a git repo" do
        file = dep_file(name: "gradlew.bat", content: "@echo\r\noff\r\n")
        reconcile([file], path: repo)
        expect(file.content).to eq("@echo\r\noff\r\n")
      end
    end
  end
end
