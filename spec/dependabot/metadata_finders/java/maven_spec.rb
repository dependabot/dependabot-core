# frozen_string_literal: true

require "spec_helper"
require "dependabot/metadata_finders/java/maven"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Java::Maven do
  it_behaves_like "a dependency metadata finder"
end
