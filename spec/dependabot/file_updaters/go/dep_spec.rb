# frozen_string_literal: true

require "dependabot/file_updaters/go/dep"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Go::Dep do
  it_behaves_like "a dependency file updater"
end
