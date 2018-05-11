# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/file_updaters/ruby/bundler/gemspec_sanitizer"

RSpec.describe Dependabot::FileUpdaters::Ruby::Bundler::GemspecSanitizer do
  let(:sanitizer) do
    described_class.new(replacement_version: replacement_version)
  end

  let(:replacement_version) { "1.5.0" }

  describe "#rewrite" do
    subject(:rewrite) { sanitizer.rewrite(content) }
    let(:content) { fixture("ruby", "gemspecs", "with_require") }

    context "with a requirement line" do
      let(:content) do
        %(require 'example/version'\nadd_dependency "require")
      end
      it { is_expected.to eq(%(\nadd_dependency "require")) }
    end

    context "with a require_relative line" do
      let(:content) do
        %(require_relative 'example/version'\nadd_dependency "require")
      end
      it { is_expected.to eq(%(\nadd_dependency "require")) }
    end

    context "with an assignment to a constant" do
      let(:content) { %(Spec.new { |s| s.version = Example::Version }) }
      it { is_expected.to eq(%(Spec.new { |s| s.version = "1.5.0" })) }

      context "that is fully capitalised" do
        let(:content) { %(Spec.new { |s| s.version = Example::VERSION }) }
        it { is_expected.to eq(%(Spec.new { |s| s.version = "1.5.0" })) }
      end

      context "that is dup-ed" do
        let(:content) { %(Spec.new { |s| s.version = Example::VERSION.dup }) }
        it { is_expected.to eq(%(Spec.new { |s| s.version = "1.5.0" })) }
      end
    end

    context "with an assignment to a variable" do
      let(:content) { "v = 'a'\n\nSpec.new { |s| s.version = v }" }
      it do
        is_expected.to eq(%(v = 'a'\n\nSpec.new { |s| s.version = "1.5.0" }))
      end
    end

    context "with an assignment to a variable" do
      let(:content) { %(Spec.new { |s| s.version = gem_version }) }
      it { is_expected.to eq(%(Spec.new { |s| s.version = "1.5.0" })) }
    end

    context "with an assignment to a string" do
      let(:content) { %(Spec.new { |s| s.version = "1.4.0" }) }
      # Don't actually do the replacement
      it { is_expected.to eq(%(Spec.new { |s| s.version = "1.4.0" })) }
    end

    # rubocop:disable Lint/InterpolationCheck
    context "with an assignment to a string-interpolated constant" do
      let(:content) { 'Spec.new { |s| s.version = "#{Example::Version}" }' }
      it { is_expected.to eq('Spec.new { |s| s.version = "#{"1.5.0"}" }') }
    end
    # rubocop:enable Lint/InterpolationCheck

    context "with a block" do
      let(:content) { fixture("ruby", "gemspecs", "with_nested_block") }
      specify { expect { sanitizer.rewrite(content) }.to_not raise_error }
    end
  end
end
