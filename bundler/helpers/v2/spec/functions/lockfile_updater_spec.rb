# typed: false
# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

RSpec.describe Functions::LockfileUpdater do
  include_context "when in a temporary bundler directory"
  include_context "when stubbing rubygems compact index"

  let(:lockfile_updater) do
    described_class.new(
      gemfile_name: "Gemfile",
      lockfile_name: "Gemfile.lock",
      dependencies: dependencies
    )
  end

  let(:dependencies) do
    [
      {
        "name" => "rspec-support",
        "version" => "3.6.0",
        "requirements" => []
      }
    ]
  end

  before do
    File.write(
      File.join(tmp_path, "Gemfile"),
      <<~GEMFILE
        source "https://rubygems.org"

        gem "rspec-support", "3.5.0"
      GEMFILE
    )

    File.write(
      File.join(tmp_path, "Gemfile.lock"),
      <<~LOCKFILE
        GEM
          remote: https://rubygems.org/
          specs:
            rspec-support (3.5.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          rspec-support (= 3.5.0)

        CHECKSUMS
          bundler (4.0.11) sha256=5bcec0fb78302e48d02ee46f10ee6e6942be647ba5b44a6d1ddfda9a240ce785
          rspec-support (3.5.0) sha256=2017eccd6868fa7c6d5373045dcad8d9b8ecb4fb533c55c7295e1cd2c61c6e83

        BUNDLED WITH
           4.0.11
      LOCKFILE
    )
  end

  describe "#run" do
    subject(:updated_lockfile) { in_tmp_folder { lockfile_updater.run } }

    it "preserves a bundler checksum from the previous lockfile" do
      expect(updated_lockfile).to include(
        "bundler (4.0.11) sha256=5bcec0fb78302e48d02ee46f10ee6e6942be647ba5b44a6d1ddfda9a240ce785"
      )
      expect(updated_lockfile).to include("rspec-support (3.6.0)")
    end
  end
end
