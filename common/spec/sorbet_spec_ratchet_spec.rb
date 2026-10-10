# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "open3"
require "shellwords"
require "tmpdir"
load File.expand_path("../../script/sorbet-spec-ratchet", __dir__)

RSpec.describe SorbetSpecRatchet do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(String) }
  let(:repository) { Dir.mktmpdir("sorbet-spec-ratchet") }

  sig { returns(String) }
  let(:script_path) { File.expand_path("../../script/sorbet-spec-ratchet", __dir__) }

  sig { returns(T::Hash[String, String]) }
  let(:git_environment) do
    {
      "GIT_AUTHOR_NAME" => "test",
      "GIT_AUTHOR_EMAIL" => "test@example.com",
      "GIT_COMMITTER_NAME" => "test",
      "GIT_COMMITTER_EMAIL" => "test@example.com",
      "GIT_TERMINAL_PROMPT" => "0"
    }
  end
  # rubocop:enable RSpec/ScatteredLet

  before do
    git("init", "--quiet", "--initial-branch=baseline")
    write_config("--dir=.\n--disable-watchman\n")
    write_spec("common/spec/example_spec.rb", "strict")
    FileUtils.mkdir_p(File.join(repository, "lib"))
    File.write(File.join(repository, "lib/library.rb"), "# typed: strict\n")
    commit
  end

  after { FileUtils.remove_entry(repository) }

  sig { params(args: String).returns(String) }
  def git(*args)
    command = Shellwords.join(["git", *args])
    stdout, stderr, status = Open3.capture3(git_environment, command, chdir: repository)
    raise stderr unless status.success?

    stdout
  end

  sig { void }
  def commit
    git("add", ".")
    git("commit", "--quiet", "-m", "Test baseline")
  end

  sig { params(content: String).void }
  def write_config(content)
    FileUtils.mkdir_p(File.join(repository, "sorbet"))
    File.write(File.join(repository, "sorbet/config"), content)
  end

  sig { params(path: String, level: String, comment: String).void }
  def write_spec(path, level, comment = "")
    filename = File.join(repository, path)
    FileUtils.mkdir_p(File.dirname(filename))
    File.write(filename, "# typed: #{level}\n# frozen_string_literal: true\n#{comment}")
    git("add", path)
  end

  sig { params(base: String).returns([String, String, Process::Status]) }
  def check(base = "HEAD")
    Open3.capture3(
      git_environment.merge("BASE_REF" => base),
      Gem.ruby,
      script_path,
      chdir: repository
    )
  end

  it "accepts unchanged legacy false files alongside checked files" do
    write_spec("common/spec/legacy_spec.rb", "false")
    commit

    stdout, stderr, status = check

    expect(status.success?).to be(true), stderr
    expect(stdout).to include("checked=1", "false=1")
  end

  it "rejects a sigil downgrade in a checked file" do
    write_spec("common/spec/example_spec.rb", "true")

    _, stderr, status = check

    expect(status.success?).to be(false)
    expect(stderr).to include("common/spec/example_spec.rb", "strict", "true")
  end

  it "rejects re-excluding a checked spec tree" do
    write_config("--dir=.\n--ignore=common/spec/\n")

    _, stderr, status = check

    expect(status.success?).to be(false)
    expect(stderr).to include("common/spec/example_spec.rb", "excluded")
  end

  it "detects effective downgrades caused by compiler configuration" do
    write_config("--dir=.\n--typed=false\n")

    _, stderr, status = check

    expect(status.success?).to be(false)
    expect(stderr).to include("common/spec/example_spec.rb", "strict", "false")
  end

  it "requires strict typing for new supported specs" do
    write_spec("common/spec/new_spec.rb", "true")

    _, stderr, status = check

    expect(status.success?).to be(false)
    expect(stderr).to include("common/spec/new_spec.rb", "strict")
  end

  it "accepts a documented new false exception" do
    write_spec(
      "common/spec/new_spec.rb",
      "false",
      "# sorbet-rspec: Child-only fixture methods are not resolved. https://srb.help/7003\n"
    )

    stdout, stderr, status = check

    expect(status.success?).to be(true), stderr
    expect(stdout).to include("false=1")
  end

  it "rejects an exception without an explanation and reference" do
    write_spec("common/spec/new_spec.rb", "false", "# sorbet-rspec: unsupported\n")

    _, stderr, status = check

    expect(status.success?).to be(false)
    expect(stderr).to include("common/spec/new_spec.rb", "reference")
  end

  it "requires a reason when a legacy false spec is changed" do
    write_spec("common/spec/legacy_spec.rb", "false")
    commit
    write_spec("common/spec/legacy_spec.rb", "false", "# Another assertion will be added here.\n")

    _, stderr, status = check

    expect(status.success?).to be(false)
    expect(stderr).to include("common/spec/legacy_spec.rb", "explanation")
  end

  it "allows an ignored higher sigil to be normalized during enrollment" do
    write_spec("other/spec/example_spec.rb", "strong")
    write_config("--dir=.\n--ignore=other/spec/\n")
    commit
    write_config("--dir=.\n")
    write_spec("other/spec/example_spec.rb", "true")

    stdout, stderr, status = check

    expect(status.success?).to be(true), stderr
    expect(stdout).to include("checked=2")
  end

  it "requires a reason when an ignored file is enrolled as false" do
    write_spec("common/spec/legacy_spec.rb", "false")
    File.write(
      File.join(repository, "sorbet/overrides.yml"),
      "ignore:\n  - ./common/spec/legacy_spec.rb\n"
    )
    write_config("--dir=.\n--typed-override=sorbet/overrides.yml\n")
    commit
    write_config("--dir=.\n")

    _, stderr, status = check

    expect(status.success?).to be(false)
    expect(stderr).to include("common/spec/legacy_spec.rb", "explanation")
  end

  it "compares an upper layer with its immediate parent rather than main" do
    git("branch", "main")
    write_spec("common/spec/parent_spec.rb", "strict")
    commit
    git("branch", "parent")
    write_spec("common/spec/parent_spec.rb", "false")

    _, stderr, status = check("parent")

    expect(status.success?).to be(false)
    expect(stderr).to include("common/spec/parent_spec.rb")
  end

  it "fails clearly when the comparison base is unavailable" do
    _, stderr, status = check("missing-parent")

    expect(status.success?).to be(false)
    expect(stderr).to include("missing-parent")
  end

  it "handles spaced paths when analyzing the parent revision" do
    write_spec("common/spec/a spaced_spec.rb", "strict")
    commit
    write_spec("common/spec/a spaced_spec.rb", "true")

    _, stderr, status = check

    expect(status.success?).to be(false)
    expect(stderr).to include("common/spec/a spaced_spec.rb", "strict", "true")
  end

  it "reports effective checking and untyped usage without counting ignored sigils" do
    write_spec("common/spec/legacy_spec.rb", "false")
    write_spec("other/spec/ignored_spec.rb", "strong")
    table_path = File.join(repository, "file-table.json")
    File.write(
      table_path,
      JSON.generate(
        files: [
          { path: "./common/spec/example_spec.rb", strict: "Strict", untyped_usages: 2 },
          { path: "./common/spec/legacy_spec.rb", strict: "False" }
        ]
      )
    )

    stdout, stderr, status = Open3.capture3(
      git_environment,
      Gem.ruby,
      script_path,
      "--report",
      table_path,
      chdir: repository
    )

    expect(status.success?).to be(true), stderr
    expect(stdout).to include("checked=1", "false=1", "ignored=1", "untyped_sends=2")
  end
end
