# typed: false
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "spec_helper"
require "dependabot/bun/file_parser/bun_lock"
require "dependabot/bun/file_parser/bun_lock/dependency_type_resolver"

# Checks the resolver against Bun's own answer, so a Bun upgrade that changes how
# packages are keyed or linked shows up here. `bun why` prints every path to a
# package and starts a path with "dev" when it begins at a devDependencies entry.
RSpec.describe Dependabot::Bun::FileParser::BunLock::DependencyTypeResolver do
  let(:project_dir) { Dir.mktmpdir }
  let(:lockfile) do
    Dependabot::Bun::FileParser::BunLock.new(
      Dependabot::DependencyFile.new(name: "bun.lock", content: File.read(File.join(project_dir, "bun.lock")))
    )
  end

  before do
    skip "bun is not installed" unless system("bun", "--version", out: File::NULL, err: File::NULL)
  end

  after { FileUtils.remove_entry(project_dir) }

  # Returns { "name@version" => true } for packages bun why reports as development only.
  def bun_why_development(dir)
    output, status = Open3.capture2e("bun", "why", "*", chdir: dir)
    output = output.force_encoding(Encoding::UTF_8)
    raise "bun why failed: #{output}" unless status.success?

    output.split(/\n{2,}/).each_with_object({}) do |block, result|
      header, *lines = block.lines.map(&:chomp)
      next if header.nil? || lines.any? { |line| line.include?("No dependents found") }

      name, _, version = header.rpartition("@")
      # Skips workspace entries such as "app@workspace:packages/app".
      next if name.empty? || !version.match?(/\A\d/)

      result["#{name}@#{version}"] = path_starts(lines).all? { |text| text.start_with?("dev ") }
    end
  end

  # The last line of each printed path, which names the workspace the path starts from.
  def path_starts(lines)
    nodes = lines.filter_map do |line|
      marker = line.index("─ ")
      [marker, line[(marker + 2)..]] if marker
    end

    nodes.each_with_index.filter_map do |(depth, text), index|
      following = nodes[index + 1]
      text if following.nil? || following.first <= depth
    end
  end

  def resolver_development
    production_by_key = described_class.new(workspaces: lockfile.workspaces, records: lockfile.records)
                                       .production_by_key

    lockfile.records.each_with_object({}) do |(key, record), result|
      next unless record.version

      result["#{record.name}@#{record.version}"] = !production_by_key.fetch(key, true)
    end
  end

  %w(simple_v1 grapher_with_subdeps wildcard workspace_dependency_types).each do |fixture_name|
    context "with the #{fixture_name} fixture" do
      before do
        fixture_dir = File.expand_path("../../../../fixtures/projects/bun/#{fixture_name}", __dir__)
        FileUtils.cp_r("#{fixture_dir}/.", project_dir)
      end

      it "agrees with bun why" do
        expected = bun_why_development(project_dir)

        expect(expected).not_to be_empty
        expect(resolver_development.slice(*expected.keys)).to eq(expected)
      end
    end
  end
end
