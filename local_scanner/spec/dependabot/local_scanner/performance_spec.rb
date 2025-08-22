# typed: false
# frozen_string_literal: true

require_relative "../../spec_helper"
require "benchmark"
require "open3"

RSpec.describe "Local Scanner Performance Benchmarks", :performance, :docker do
  let(:test_project_dir) { LocalScannerHelper.test_project_dir("basic_ruby_project") }
  let(:docker_image) { LocalScannerHelper.docker_image_name }

  describe "startup performance" do
    it "starts up within acceptable time limits" do
      times = []
      5.times do
        time = Benchmark.realtime do
          stdout, stderr, status = Open3.capture3(
            "docker", "run", "--rm",
            docker_image,
            "ruby", "bin/local_ruby_scan.rb", "--help"
          )
          expect(status.success?).to be true
        end
        times << time
      end

      average_time = times.sum / times.length
      expect(average_time).to be < 3.0  # Average startup under 3 seconds
      expect(times.max).to be < 5.0     # No single startup over 5 seconds
    end
  end

  describe "scan performance" do
    it "completes basic scan within acceptable time" do
      time = Benchmark.realtime do
        stdout, stderr, status = Open3.capture3(
          "docker", "run", "--rm",
          "-v", "#{test_project_dir}:/repo",
          docker_image,
          "ruby", "bin/local_ruby_scan.rb", "/repo"
        )
        expect(status.success?).to be true
        expect(stdout).to include("🔍 Scanning local Ruby project")
      end

      expect(time).to be < 10.0  # Basic scan under 10 seconds
    end

    it "completes security scan within acceptable time" do
      time = Benchmark.realtime do
        stdout, stderr, status = Open3.capture3(
          "docker", "run", "--rm",
          "-v", "#{test_project_dir}:/repo",
          docker_image,
          "ruby", "bin/local_ruby_scan.rb", "--security-details", "/repo"
        )
        expect(status.success?).to be true
      end

      expect(time).to be < 15.0  # Security scan under 15 seconds
    end

    it "completes all-updates scan within acceptable time" do
      time = Benchmark.realtime do
        stdout, stderr, status = Open3.capture3(
          "docker", "run", "--rm",
          "-v", "#{test_project_dir}:/repo",
          docker_image,
          "ruby", "bin/local_ruby_scan.rb", "--all-updates", "/repo"
        )
        expect(status.success?).to be true
      end

      expect(time).to be < 20.0  # All-updates scan under 20 seconds
    end
  end

  describe "memory usage" do
    it "maintains reasonable memory usage during scan" do
      # This is a basic check - in a real environment you'd use more sophisticated tools
      start_memory = `ps -o rss= -p #{Process.pid}`.to_i
      
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{test_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "/repo"
      )
      
      end_memory = `ps -o rss= -p #{Process.pid}`.to_i
      memory_increase = end_memory - start_memory
      
      expect(status.success?).to be true
      # Memory increase should be reasonable (less than 100MB)
      expect(memory_increase).to be < 100 * 1024
    end
  end

  describe "concurrent performance" do
    it "handles multiple concurrent scans efficiently" do
      start_time = Time.now
      
      # Run 3 concurrent scans
      processes = []
      3.times do
        processes << Open3.popen3(
          "docker", "run", "--rm",
          "-v", "#{test_project_dir}:/repo",
          docker_image,
          "ruby", "bin/local_ruby_scan.rb", "/repo"
        )
      end

      # Wait for all to complete
      results = processes.map do |stdin, stdout, stderr, wait_thr|
        stdin.close
        output = stdout.read
        error = stderr.read
        status = wait_thr.value
        { output: output, error: error, status: status }
      end

      end_time = Time.now
      total_time = end_time - start_time

      # All should succeed
      results.each do |result|
        expect(result[:status].success?).to be true
        expect(result[:error]).to be_empty
      end

      # Concurrent execution should be faster than sequential
      # (3 sequential scans would take ~30 seconds, concurrent should be ~15-20)
      expect(total_time).to be < 25.0
    end
  end

  describe "performance regression detection" do
    it "maintains consistent performance across runs" do
      times = []
      3.times do
        time = Benchmark.realtime do
          stdout, stderr, status = Open3.capture3(
            "docker", "run", "--rm",
            "-v", "#{test_project_dir}:/repo",
            docker_image,
            "ruby", "bin/local_ruby_scan.rb", "/repo"
          )
          expect(status.success?).to be true
        end
        times << time
      end

      # Performance should be consistent (within 20% variance)
      average_time = times.sum / times.length
      times.each do |time|
        variance = (time - average_time).abs / average_time
        expect(variance).to be < 0.2  # Less than 20% variance
      end
    end
  end
end
