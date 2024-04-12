# typed: false
# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"
require "bundler/lockfile_parser"

RSpec.describe Functions::FastSpecParser do
  describe "#initialize" do
    subject { described_class.new(lockfile_path) }

    let(:lockfile_path) { fixture_path("lockfiles", lockfile_name) }
    let(:lockfile) { fixture("lockfiles", lockfile_name) }
    let(:lockfile_name) { "updater.lock" }

    it "should return the same results as Bundler::LockfileParser" do
      expect(subject.specs.to_a.sort).to eq(Bundler::LockfileParser.new(lockfile).specs.map { |x| x.name.to_s }.uniq)
    end
  end
end
