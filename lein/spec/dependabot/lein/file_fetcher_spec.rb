# frozen_string_literal: true

require "spec_helper"
require "dependabot/lein/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Lein::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  it { expect(true).to eq(false) }
end
