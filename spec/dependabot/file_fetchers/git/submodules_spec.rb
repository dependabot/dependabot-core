# frozen_string_literal: true
require "dependabot/file_fetchers/git/submodules"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Git::Submodules do
  it_behaves_like "a dependency file fetcher"
end
