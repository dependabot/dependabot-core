# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_updaters/artifact_updater"

RSpec.describe Dependabot::FileUpdaters::ArtifactUpdater do
  let(:updater) do
    described_class.new(
      repo_contents_path: repo_contents_path,
      target_directory: target_directory
    )
  end

  let(:target_directory) do
    File.join(repo_contents_path, directory, "vendor/cache")
  end
  let(:project_name) { "vendor_gems" }
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:directory) { "/" }
  let(:only_paths) { nil }

  let(:updated_files) do
    updater.updated_files(base_directory: directory, only_paths: only_paths)
  end

  after do
    FileUtils.remove_entry repo_contents_path
  end

  describe "#updated_files" do
    before do
      in_cloned_repository(repo_contents_path) do
        # change a file like an updater would
        next unless File.exist?("vendor/cache/business-1.4.0.gem")

        `mv vendor/cache/business-1.4.0.gem vendor/cache/business-1.5.0.gem`
        `echo change >> vendor/cache/test-change.txt`
      end
    end

    it "returns the updated files" do
      expect(updated_files.map(&:name)).to eq(
        %w(
          vendor/cache/business-1.4.0.gem
          vendor/cache/test-change.txt
          vendor/cache/business-1.5.0.gem
        )
      )
    end

    it "does not mark the files as vendored" do
      expect(updated_files).not_to include(be_vendored_file)
    end

    it "marks binary files as such" do
      file = updated_files.find do |f|
        f.name == "vendor/cache/business-1.5.0.gem"
      end

      expect(file).to be_binary
    end

    it "marks created files as such" do
      file = updated_files.find do |f|
        f.name == "vendor/cache/business-1.5.0.gem"
      end

      expect(file.deleted).to be_falsey
      expect(file).not_to be_deleted
      expect(file.operation).to eq Dependabot::DependencyFile::Operation::CREATE
    end

    it "marks updated files as such" do
      file = updated_files.find do |f|
        f.name == "vendor/cache/test-change.txt"
      end

      expect(file.deleted).to be_falsey
      expect(file).not_to be_deleted
      expect(file.operation).to eq Dependabot::DependencyFile::Operation::UPDATE
    end

    it "marks deleted files as such" do
      file = updated_files.find do |f|
        f.name == "vendor/cache/business-1.4.0.gem"
      end

      expect(file.deleted).to be_truthy
      expect(file).to be_deleted
      expect(file.operation).to eq Dependabot::DependencyFile::Operation::DELETE
    end

    it "base64 encodes binary files" do
      file = updated_files.find do |f|
        f.name == "vendor/cache/business-1.5.0.gem"
      end

      expect(file.content_encoding).to eq("base64")
    end

    it "ignores files that are in the .gitignore" do
      in_cloned_repository(repo_contents_path) do
        `touch vendor/cache/ignored.txt`
      end

      expect(updated_files.map(&:name)).not_to include(
        "vendor/cache/ignored.txt"
      )
    end

    it "ignores files that are not in the vendor directory" do
      in_cloned_repository(repo_contents_path) do
        `touch some-file.txt`
      end

      expect(updated_files.map(&:name)).not_to include(
        "some-file.txt"
      )
    end

    context "with iso-8859 files" do
      before do
        in_cloned_repository(repo_contents_path) do
          File.write("vendor/cache/utf8.txt", "special ü".encode("utf-8"))
          File.write("vendor/cache/iso8859.txt", "special ü".encode("iso-8859-1"))
        end
      end

      it "marks binary files as such" do
        file = updated_files.find do |f|
          f.name == "vendor/cache/iso8859.txt"
        end

        expect(file).to be_binary
      end

      it "does not mark all files as binary" do
        file = updated_files.find do |f|
          f.name == "vendor/cache/utf8.txt"
        end

        expect(file).not_to be_binary
      end
    end

    context "when in a directory" do
      let(:project_name) { "nested_vendor_gems" }
      let(:directory) { "nested" }

      before do
        in_cloned_repository(repo_contents_path) do
          # change a file like an updater would
          `mv nested/vendor/cache/business-1.4.0.gem \
          nested/vendor/cache/business-1.5.0.gem`
        end
      end

      it "does not include the directory in the name" do
        expect(updated_files.first.name).not_to include("nested")
      end

      it "sets the right directory" do
        expect(updated_files.first.directory).to eq("/nested")
      end
    end

    context "when given a relative target directory" do
      let(:target_directory) do
        "vendor/cache"
      end

      it "returns the updated files" do
        expect(updated_files.map(&:name)).to eq(
          %w(
            vendor/cache/business-1.4.0.gem
            vendor/cache/test-change.txt
            vendor/cache/business-1.5.0.gem
          )
        )
      end
    end

    context "when given specific paths to check" do
      let(:only_paths) do
        [
          "vendor/cache/test-change.txt",
          "vendor/cache/not-present.txt"
        ]
      end

      it "only returns any changes to the file paths specified" do
        expect(updated_files.map(&:name)).to eq(
          %w(
            vendor/cache/test-change.txt
          )
        )
      end
    end
  end

  describe "binary encoding" do
    let(:project_name) { "binary_files" }

    %w(test.zip test_bin test.png test.gem .bundlecache).each do |name|
      it "marks #{name} files correctly" do
        in_cloned_repository(repo_contents_path) do
          `mv vendor/cache/#{name} vendor/cache/new_#{name}`
        end

        file = updated_files.find { |f| f.name == "vendor/cache/new_#{name}" }

        expect(file).to be_binary
      end
    end
  end

  private

  def in_cloned_repository(repo_contents_path, &block)
    Dir.chdir(repo_contents_path, &block)
  end
end
