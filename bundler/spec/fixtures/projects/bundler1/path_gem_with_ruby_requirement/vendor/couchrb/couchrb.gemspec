# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "couchrb"
  spec.version       = "0.9.0"
  spec.authors       = ["nicholas a. evans"]
  spec.email         = ["<nevans@410labs.com>"]

  spec.summary       = %q{CouchDB client library.}
  spec.description   = %q{CouchRb provides a ruby-flavored interface to CouchDB.  The basic resources try to follow the CouchDB API as closely as possible, but many additional features are available.}
  spec.homepage      = "https://github.com/410labs/couchrb"

  spec.required_ruby_version = ">= 1.9.3"

  spec.add_dependency "ice_nine"
end
