# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"

RSpec.describe Dependabot::DependencyFile do
  around do |example|
    repo_path = File.expand_path("spec/fixtures/projects/simple")
    Dir.chdir(repo_path) { example.run }
  end

  let(:file) { described_class.new(name: "Gemfile", content: "a") }

  describe "#path" do
    subject { file.path }

    context "without a directory specified" do
      it { is_expected.to eq("/Gemfile") }
    end

    context "with a directory specified" do
      let(:file) do
        described_class.new(name: "Gemfile", content: "a", directory: directory)
      end

      context "when starting and ending with a slash" do
        let(:directory) { "/path/to/files/" }

        it { is_expected.to eq("/path/to/files/Gemfile") }
      end

      context "when not starting or ending with a slash" do
        let(:directory) { "path/to/files" }

        it { is_expected.to eq("/path/to/files/Gemfile") }
      end

      context "when the filename includes a '..'" do
        let(:directory) { "path/to/files" }
        let(:file) do
          described_class.new(
            name: "../Gemfile",
            content: "a",
            directory: directory
          )
        end

        it { is_expected.to eq("/path/to/Gemfile") }
      end
    end
  end

  describe "#directory" do
    subject { file.directory }

    context "without a directory specified" do
      it { is_expected.to eq("/") }
    end

    context "with a directory specified" do
      let(:file) do
        described_class.new(name: "Gemfile", content: "a", directory: directory)
      end

      context "when starting and ending with a slash" do
        let(:directory) { "/path/to/files" }

        it { is_expected.to eq("/path/to/files") }
      end

      context "when not starting or ending with a slash" do
        let(:directory) { "path/to/files" }

        it { is_expected.to eq("/path/to/files") }
      end
    end
  end

  describe "#to_h" do
    subject(:file_hash) { file.to_h }

    context "with a non-symlink" do
      it "returns the correct array" do
        expect(file_hash).to eq(
          "name" => "Gemfile",
          "content" => "a",
          "directory" => "/",
          "type" => "file",
          "mode" => "100644",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => Dependabot::DependencyFile::Operation::UPDATE
        )
      end

      it "has the correct operation properties" do
        expect(file.deleted).to be_falsey
        expect(file).not_to be_deleted
        expect(file.operation).to eq Dependabot::DependencyFile::Operation::UPDATE
      end
    end

    context "with a symlink" do
      let(:file) do
        described_class.new(
          name: "Gemfile",
          content: "a",
          type: "symlink",
          symlink_target: "nested/Gemfile"
        )
      end

      it "returns the correct array" do
        expect(file_hash).to eq(
          "name" => "Gemfile",
          "content" => "a",
          "directory" => "/",
          "mode" => nil,
          "type" => "symlink",
          "support_file" => false,
          "symlink_target" => "nested/Gemfile",
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => Dependabot::DependencyFile::Operation::UPDATE
        )
      end

      it "has the correct operation properties" do
        expect(file.deleted).to be_falsey
        expect(file).not_to be_deleted
        expect(file.operation).to eq Dependabot::DependencyFile::Operation::UPDATE
      end
    end

    context "with a new file" do
      let(:file) do
        described_class.new(
          name: "Gemfile",
          content: "a",
          operation: Dependabot::DependencyFile::Operation::CREATE
        )
      end

      it "returns the correct array" do
        expect(file_hash).to eq(
          "name" => "Gemfile",
          "content" => "a",
          "directory" => "/",
          "mode" => "100644",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => Dependabot::DependencyFile::Operation::CREATE
        )
      end

      it "has the correct operation properties" do
        expect(file.deleted).to be_falsey
        expect(file).not_to be_deleted
        expect(file.operation).to eq Dependabot::DependencyFile::Operation::CREATE
      end
    end

    context "with a changed file" do
      let(:file) do
        described_class.new(
          name: "Gemfile",
          content: "a",
          operation: Dependabot::DependencyFile::Operation::UPDATE
        )
      end

      it "returns the correct array" do
        expect(file_hash).to eq(
          "name" => "Gemfile",
          "content" => "a",
          "directory" => "/",
          "mode" => "100644",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => Dependabot::DependencyFile::Operation::UPDATE
        )
      end

      it "has the correct operation properties" do
        expect(file.deleted).to be_falsey
        expect(file).not_to be_deleted
        expect(file.operation).to eq Dependabot::DependencyFile::Operation::UPDATE
      end
    end

    context "with a deleted file" do
      let(:file) do
        described_class.new(
          name: "Gemfile",
          content: "a",
          operation: Dependabot::DependencyFile::Operation::DELETE
        )
      end

      it "returns the correct array" do
        expect(file_hash).to eq(
          "name" => "Gemfile",
          "content" => "a",
          "directory" => "/",
          "mode" => "100644",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => true,
          "operation" => Dependabot::DependencyFile::Operation::DELETE
        )
      end

      it "has the correct operation properties" do
        expect(file.deleted).to be_truthy
        expect(file).to be_deleted
        expect(file.operation).to eq Dependabot::DependencyFile::Operation::DELETE
      end
    end

    context "with a deleted file using the legacy initializer method" do
      let(:file) do
        described_class.new(
          name: "Gemfile",
          content: "a",
          deleted: true
        )
      end

      it "returns the correct array" do
        expect(file_hash).to eq(
          "name" => "Gemfile",
          "content" => "a",
          "directory" => "/",
          "mode" => "100644",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => true,
          "operation" => Dependabot::DependencyFile::Operation::DELETE
        )
      end

      it "has the correct operation properties" do
        expect(file.deleted).to be_truthy
        expect(file).to be_deleted
        expect(file.operation).to eq Dependabot::DependencyFile::Operation::DELETE
      end
    end

    context "with a deleted file using the legacy setter method" do
      let(:file) do
        file = described_class.new(
          name: "Gemfile",
          content: "a"
        )
        file.deleted = true
        file
      end

      it "returns the correct array" do
        expect(file_hash).to eq(
          "name" => "Gemfile",
          "content" => "a",
          "directory" => "/",
          "mode" => "100644",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => true,
          "operation" => Dependabot::DependencyFile::Operation::DELETE
        )
      end

      it "has the correct operation properties" do
        expect(file.deleted).to be_truthy
        expect(file).to be_deleted
        expect(file.operation).to eq Dependabot::DependencyFile::Operation::DELETE
      end
    end
  end

  describe "#==" do
    context "when two dependency files are equal" do
      let(:file1) { described_class.new(name: "Gemfile", content: "a") }
      let(:file2) { described_class.new(name: "Gemfile", content: "a") }

      specify { expect(file1).to eq(file2) }
    end

    context "when two dependency files are equal, but one is a support file" do
      let(:file1) { described_class.new(name: "Gemfile", content: "a") }
      let(:file2) do
        described_class.new(name: "Gemfile", content: "a", support_file: true)
      end

      specify { expect(file1).to eq(file2) }
    end

    context "when two dependency files are equal, but one is a vendored file" do
      let(:file1) { described_class.new(name: "Gemfile", content: "a") }
      let(:file2) do
        described_class.new(name: "Gemfile", content: "a", vendored_file: true)
      end

      specify { expect(file1).to eq(file2) }
    end

    context "when two dependency files are not equal" do
      let(:file1) { described_class.new(name: "Gemfile", content: "a") }
      let(:file2) { described_class.new(name: "Gemfile", content: "b") }

      specify { expect(file1).not_to eq(file2) }
    end
  end

  describe "#decoded_content" do
    context "when dealing with a base64 encoded content" do
      let(:file) do
        described_class.new(
          name: "example.gem",
          content_encoding: Dependabot::DependencyFile::ContentEncoding::BASE64,
          content: "YWJj\n"
        )
      end

      it "decodes the content to its original encoding" do
        expect(file.decoded_content).to eq("abc")
      end
    end

    context "when dealing with a utf-8 encoded content" do
      let(:file) do
        described_class.new(
          name: "example.gem",
          content: "abc"
        )
      end

      it "returns the unencoded content" do
        expect(file.decoded_content).to eq("abc")
      end
    end
  end

  describe "#vendored_file?" do
    it "is false by default" do
      expect(file.vendored_file?).to be false
    end

    context "when set to true during creation" do
      let(:file) { described_class.new(name: "Gemfile", content: "a", vendored_file: true) }

      it "is true" do
        expect(file.vendored_file?).to be true
      end
    end
  end
end
