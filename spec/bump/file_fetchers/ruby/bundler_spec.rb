# frozen_string_literal: true
require "bump/file_fetchers/ruby/bundler"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Bump::FileFetchers::Ruby::Bundler do
  it_behaves_like "a dependency file fetcher"
end
