# frozen_string_literal: true

require "spec_helper"

$LOAD_PATH.unshift(File.expand_path("../helpers/lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("../helpers/monkey_patches", __dir__))

# Bundler monkey patches
require "definition_ruby_version_patch"
require "definition_bundler_version_patch"
require "git_source_patch"

require "functions"

RSpec.shared_context "in a temporary bundler directory" do
  let(:gemfile_name) { "Gemfile" }
  let(:lockfile_name) { "Gemfile.lock" }

  let(:gemfile_fixture) do
    fixture("ruby", "gemfiles", gemfile_fixture_name)
  end

  # We don't always need a lockfile, so define a nil value tests can override
  let(:lockfile_fixture_name) do
    nil
  end

  let(:lockfile_fixture) do
    fixture("ruby", "lockfiles", lockfile_fixture_name)
  end

  let(:tmp_path) do
    dir = Dir.mktmpdir("native_helper_spec_", "tmp")
    Pathname.new(dir).expand_path
  end

  before do
    File.write(File.join(tmp_path, gemfile_name), gemfile_fixture)

    if lockfile_fixture_name
      File.write(File.join(tmp_path, lockfile_name), lockfile_fixture)
    end
  end

  def in_tmp_folder(&block)
    Dir.chdir(tmp_path, &block)
  end
end
