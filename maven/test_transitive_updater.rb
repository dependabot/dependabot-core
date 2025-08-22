#!/usr/bin/env ruby
# Test script to verify TransitiveDependencyUpdater functionality

require_relative "lib/dependabot/maven"
require "dependabot/dependency"
require "dependabot/dependency_file"

# Enable the experiment
module Dependabot
  module Experiments
    def self.enabled?(experiment)
      experiment == :maven_transitive_dependencies
    end
  end
end

# Create a sample dependency and pom file
dependency = Dependabot::Dependency.new(
  name: "com.google.guava:guava",
  version: "23.6-jre",
  requirements: [
    {
      file: "pom.xml",
      requirement: "23.6-jre",
      groups: [],
      source: nil,
      metadata: { packaging_type: "jar" }
    }
  ],
  package_manager: "maven"
)

pom_content = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>my-app</artifactId>
    <version>1.0.0</version>
    <dependencies>
      <dependency>
        <groupId>com.google.guava</groupId>
        <artifactId>guava</artifactId>
        <version>23.6-jre</version>
      </dependency>
    </dependencies>
  </project>
XML

dependency_file = Dependabot::DependencyFile.new(
  name: "pom.xml",
  content: pom_content
)

begin
  updater = Dependabot::Maven::UpdateChecker::TransitiveDependencyUpdater.new(
    dependency: dependency,
    dependency_files: [dependency_file],
    target_version_details: {
      version: Dependabot::Maven::Version.new("23.7-jre"),
      source_url: "https://repo.maven.apache.org/maven2"
    },
    credentials: [],
    ignored_versions: []
  )

  puts "Testing TransitiveDependencyUpdater..."
  puts "Update possible: #{updater.update_possible?}"
  puts "Dependencies depending on target: #{updater.dependencies_depending_on_target.length}"
  
  if updater.update_possible?
    updated_deps = updater.updated_dependencies
    puts "Updated dependencies count: #{updated_deps.length}"
    
    updated_deps.each do |dep|
      puts "  - #{dep.name}: #{dep.previous_version} -> #{dep.version}"
    end
  else
    puts "Update not possible"
  end
  
  puts "\nTesting complete successfully!"
rescue => e
  puts "Error testing TransitiveDependencyUpdater: #{e.message}"
  puts e.backtrace.first(5)
end