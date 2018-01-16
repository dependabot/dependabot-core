# frozen_string_literal: true

require "dependabot/file_fetchers/elixir/hex"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Elixir::Hex do
  it_behaves_like "a dependency file fetcher"
end
