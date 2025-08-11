# rubocop:disable all
# typed: false
# frozen_string_literal: true

require "dependabot/file_fetchers/base"
require "dependabot/config/update_config"
require "dependabot/experiments"

# Command to run this test: rspec common/lib/dependabot/file_fetchers/base_exclude_spec.rb
RSpec.describe Dependabot::FileFetchers::Base do
  let(:source) { Dependabot::Source.new(provider: "github", repo: "some/random-repo", directory: "/", branch: "main") }
  let(:creds)  { [] }
  let(:opts)   { {} }

  let(:update_config) do
    Dependabot::Config::UpdateConfig.new(
      ignore_conditions: [],
      commit_message_options: nil,
      exclude_paths: ["src/test/assets", "vendor/**"]
    )
  end

  subject(:fetcher) do
    Class.new(Dependabot::FileFetchers::Base) do
      def fetch_files = []
    end.new(
      source: source,
      credentials: creds,
      repo_contents_path: nil,
      options: opts,
      update_config: update_config
    )
  end

  before do
    # Prevent Dependabot from hitting real GitHub and default-branch logic
    allow(fetcher).to receive(:commit).and_return("dummy-sha")
    allow(fetcher)
      .to(receive(:_full_specification_for)
      .and_wrap_original { |_, path, **| { provider: "github", repo: source.repo, path: path, commit: "dummy-sha" } })

    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_exclude_paths_subdirectory_manifest_files).and_return(true)

    # Stub the lowest-level fetch, but return *all* immediate children
    allow(fetcher)
      .to receive(:_fetch_repo_contents_fully_specified) do |_, _, path, _|
      case path
      when "", "/"
        [
          OpenStruct.new(name: "foo.rb", path: "foo.rb", type: "file"),
          OpenStruct.new(name: "vendor", path: "vendor", type: "dir"),
          OpenStruct.new(name: "src", path: "src", type: "dir")
        ]
      when "src"
        [
          OpenStruct.new(name: "bar.rb",    path: "src/bar.rb",    type: "file"),
          OpenStruct.new(name: "zoo.rb",    path: "src/zoo.rb",    type: "file"),
          OpenStruct.new(name: "test",      path: "src/test",      type: "dir"),
          OpenStruct.new(name: "assets",    path: "src/test/assets", type: "dir")
        ]
      when "src/test"
        [
          OpenStruct.new(name: "assets", path: "src/test/assets", type: "dir"),
          OpenStruct.new(name: "helper.rb", path: "src/test/helper.rb", type: "file")
        ]
      when "src/test/assets"
        [
          OpenStruct.new(name: "go.mod", path: "src/test/assets/go.mod", type: "file")
        ]
      when "vendor"
        [
          OpenStruct.new(name: "gemA", path: "vendor/gemA", type: "dir")
        ]
      when "vendor/gemA"
        [
          OpenStruct.new(name: "nested.txt", path: "vendor/gemA/nested.txt", type: "file")
        ]
      when "others"
        [
          OpenStruct.new(name: "abc",       path: "others/abc",       type: "dir"),
          OpenStruct.new(name: "abcd",      path: "others/abcd",      type: "dir"),
          OpenStruct.new(name: "abcde",     path: "others/abcde",     type: "dir"),
        ]
      else
        []
      end
    end
  end

  describe "_fetch_repo_contents" do
    it "completely blocks a directory if its path is exactly excluded" do
      expect(fetcher.send(:_fetch_repo_contents, "src/test/assets")).to eq([])
    end

    it "filters out excluded children after fetching" do
      paths = fetcher.send(:_fetch_repo_contents, "src").map(&:path)
      expect(paths).to include("src/bar.rb", "src/test")
      expect(paths).not_to include("src/test/assets")
    end

    it "skips any subpaths under vendor/ but retains the vendor folder itself" do
      expect(fetcher.send(:_fetch_repo_contents, "vendor")).to eq([])
    end

    it "fetches and filters children under non-excluded parent" do
      paths = fetcher.send(:_fetch_repo_contents, "src/test").map(&:path)
      # stub returned two entries, assets should be excluded leaving helper.rb
      expect(paths).to match_array(["src/test/helper.rb"])
    end

    it "lets other top-level entries through" do
      paths = fetcher.send(:_fetch_repo_contents, "src").map(&:path)
      expect(paths).to match_array(["src/bar.rb", "src/zoo.rb", "src/test"])
    end

    it "glob-excludes vendor deeper paths" do
      # direct fetch of vendor/gemA should be blocked
      expect(fetcher.send(:_fetch_repo_contents, "vendor/gemA")).to eq([])
    end

    it "excludes a single file without dropping its parent directory" do
      fetcher.instance_variable_set(:@exclude_paths, %w(vendor/** src/test/helper.rb))

      paths = fetcher.send(:_fetch_repo_contents, "src/test").map(&:path)
      expect(paths).not_to include("src/test/helper.rb")
      expect(paths).to include("src/test/assets")
    end

    it "excludes the right folder" do
      fetcher.instance_variable_set(:@exclude_paths, %w(others/abc))

      paths = fetcher.send(:_fetch_repo_contents, "others").map(&:path)
      expect(paths).not_to include("others/abc")
      expect(paths).to include("others/abcd")
      expect(paths).to include("others/abcde")
    end

    it "filters out individual files by glob but still descends into the folder" do
      fetcher.instance_variable_set(:@exclude_paths, %w(src/*.rb))

      entries = fetcher.send(:_fetch_repo_contents, "src")
      paths   = entries.map(&:path)

      expect(paths).not_to include("src/bar.rb")
      expect(entries.map(&:type)).to include("dir")
      expect(paths).to include("src/test")
      expect(paths).to include("src/test/assets")
    end
  end

  describe "repo_contents" do
    it "completely blocks a directory if its path is exactly excluded" do
      expect(fetcher.send(:repo_contents, dir: "src/test/assets")).to eq([])
    end

    it "filters out excluded children after fetching" do
      paths = fetcher.send(:repo_contents, dir: "src").map(&:path)
      expect(paths).to include("src/bar.rb", "src/test")
      expect(paths).not_to include("src/test/assets")
    end

    it "skips any subpaths under vendor/ but retains the vendor folder itself" do
      expect(fetcher.send(:repo_contents, dir: "vendor")).to eq([])
    end

    it "fetches and filters children under non-excluded parent" do
      paths = fetcher.send(:repo_contents, dir: "src/test").map(&:path)
      # stub returned two entries, assets should be excluded leaving helper.rb
      expect(paths).to match_array(["src/test/helper.rb"])
    end

    it "lets other top-level entries through" do
      paths = fetcher.send(:repo_contents, dir: "src").map(&:path)
      expect(paths).to match_array(["src/bar.rb", "src/zoo.rb", "src/test"])
    end

    it "glob-excludes vendor deeper paths" do
      # direct fetch of vendor/gemA should be blocked
      expect(fetcher.send(:repo_contents, dir: "vendor/gemA")).to eq([])
    end

    it "excludes a single file without dropping its parent directory" do
      fetcher.instance_variable_set(:@exclude_paths, %w(vendor/** src/test/helper.rb))

      paths = fetcher.send(:repo_contents, dir: "src/test").map(&:path)
      expect(paths).not_to include("src/test/helper.rb")
      expect(paths).to include("src/test/assets")
    end

    it "excludes the right folder" do
      fetcher.instance_variable_set(:@exclude_paths, %w(others/abcd))

      paths = fetcher.send(:repo_contents, dir: "others").map(&:path)
      expect(paths).not_to include("others/abcd")
      expect(paths).to include("others/abc")
      expect(paths).to include("others/abcde")
    end

    it "filters out individual files by glob but still descends into the folder" do
      fetcher.instance_variable_set(:@exclude_paths, %w(src/*.rb))

      entries = fetcher.send(:repo_contents, dir: "src")
      paths   = entries.map(&:path)

      expect(paths).not_to include("src/bar.rb")
      expect(entries.map(&:type)).to include("dir")
      expect(paths).to include("src/test")
      expect(paths).to include("src/test/assets")
    end
  end
end
