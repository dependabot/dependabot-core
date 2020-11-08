# frozen_string_literal: true

require "spec_helper"
require "dependabot/lein/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Lein::FileParser do
  it_behaves_like "a dependency file parser"

  it { expect(true).to eq(false) }
end
