# frozen_string_literal: true

require 'spec_helper'
require 'dependabot/cocoapods/requirement'
require 'dependabot/cocoapods/version'

RSpec.describe Dependabot::CocoaPods::Requirement do
  subject(:requirement) { described_class.new(requirement_array) }
  let(:requirement_array) { ['>= 1.0.0', '< 2.0.0'] }

  describe '.new' do
    subject { described_class.new(requirement_array) }

    context 'with nil' do
      let(:requirement_array) { ['invalid'] }
      it 'raises a helpful error' do
        expect { subject }.to raise_error(ArgumentError)
      end
    end

    context 'with range requirement' do
      let(:requirement_array) { ['>= 1.0.0', '< 2.0.0'] }
      it { is_expected.to eq(described_class.new('>= 1.0.0', '< 2.0.0')) }

      context 'which uses a <= operator' do
        let(:requirement_array) { ['>= 1.0.0', '<= 2.0.0'] }
        it { is_expected.to eq(described_class.new('>= 1.0.0', '<= 2.0.0')) }
      end
    end

    context 'with exact requirement' do
      let(:requirement_array) { ['= 1.0.0'] }
      it { is_expected.to eq(described_class.new('= 1.0.0')) }
      it {
        is_expected.to be_satisfied_by(
          Pod::Version.new('1.0.0')
        )
      }
      it {
        is_expected.to_not be_satisfied_by(
          Dependabot::CocoaPods::Version.new('1.0.1')
        )
      }

      context 'specified as a version' do
        let(:requirement_array) { ['1.0.0'] }
        it { is_expected.to eq(described_class.new('= 1.0.0')) }
      end
    end
  end

  describe '#satisfied_by?' do
    subject { requirement.satisfied_by?(version) }

    context 'with a Pod::Version' do
      context 'for the current version' do
        let(:version) { Dependabot::CocoaPods::Version.new('1.0.0') }
        it { is_expected.to eq(true) }
      end

      context 'for an out-of-range version' do
        let(:version) { Dependabot::CocoaPods::Version.new('2.0.1') }
        it { is_expected.to eq(false) }
      end
    end
  end
end
