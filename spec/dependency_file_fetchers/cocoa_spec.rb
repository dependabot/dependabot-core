# frozen_string_literal: true
require "bump/dependency_file_fetchers/cocoa"
require_relative "./shared_examples_for_file_fetchers"

RSpec.describe Bump::DependencyFileFetchers::Cocoa do
  it_behaves_like "a dependency file fetcher"
end
