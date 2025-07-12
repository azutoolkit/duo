#!/usr/bin/env crystal

require "option_parser"
require "process"
require "yaml"
require "json"

# h2spec compliance testing tool for Duo HTTP/2 implementation
class H2SpecRunner
  private getter server_host : String
  private getter server_port : Int32
  private getter h2spec_path : String
  private getter output_format : String
  private getter verbose : Bool
  private getter timeout : Int32

  def initialize(@server_host = "localhost", @server_port = 8080, 
                 @h2spec_path = "h2spec", @output_format = "json", 
                 @verbose = false, @timeout = 30)
  end

  def run_tests : ComplianceReport
    puts "Starting h2spec compliance tests against #{@server_host}:#{@server_port}"
    
    # Check if h2spec is available
    unless h2spec_available?
      raise "h2spec not found. Please install h2spec first: https://github.com/summerwind/h2spec"
    end

    # Build h2spec command
    command = build_h2spec_command
    
    puts "Running: #{command.join(" ")}" if @verbose
    
    # Run h2spec
    result = Process.run(command.join(" "), 
                        shell: true,
                        output: Process::Redirect::Pipe,
                        error: Process::Redirect::Pipe,
                        timeout: @timeout)
    
    # Parse results
    parse_results(result)
  end

  def run_specific_tests(test_categories : Array(String)) : ComplianceReport
    puts "Running specific h2spec tests: #{test_categories.join(", ")}"
    
    command = build_h2spec_command(test_categories)
    
    puts "Running: #{command.join(" ")}" if @verbose
    
    result = Process.run(command.join(" "), 
                        shell: true,
                        output: Process::Redirect::Pipe,
                        error: Process::Redirect::Pipe,
                        timeout: @timeout)
    
    parse_results(result)
  end

  def generate_report(report : ComplianceReport) : String
    case @output_format
    when "json"
      report.to_json
    when "yaml"
      report.to_yaml
    when "text"
      report.to_text
    else
      report.to_json
    end
  end

  private def h2spec_available? : Bool
    result = Process.run("which #{@h2spec_path}", 
                        shell: true,
                        output: Process::Redirect::Null,
                        error: Process::Redirect::Null)
    result.success?
  end

  private def build_h2spec_command(test_categories : Array(String)? = nil) : Array(String)
    command = [
      @h2spec_path,
      "-p", @server_port.to_s,
      "-h", @server_host,
      "--format", @output_format,
      "--timeout", @timeout.to_s
    ]
    
    if @verbose
      command << "--verbose"
    end
    
    if test_categories
      command << "--tests"
      command << test_categories.join(",")
    end
    
    command
  end

  private def parse_results(result : Process::Result) : ComplianceReport
    if result.success?
      parse_successful_results(result)
    else
      parse_failed_results(result)
    end
  end

  private def parse_successful_results(result : Process::Result) : ComplianceReport
    case @output_format
    when "json"
      parse_json_results(result.output_message)
    when "yaml"
      parse_yaml_results(result.output_message)
    else
      parse_text_results(result.output_message)
    end
  end

  private def parse_failed_results(result : Process::Result) : ComplianceReport
    ComplianceReport.new(
      success: false,
      exit_code: result.exit_code,
      total_tests: 0,
      passed_tests: 0,
      failed_tests: 0,
      skipped_tests: 0,
      error_message: result.error_message,
      test_results: [] of TestResult
    )
  end

  private def parse_json_results(output : String) : ComplianceReport
    begin
      data = JSON.parse(output)
      
      ComplianceReport.new(
        success: true,
        exit_code: 0,
        total_tests: data["total"]?.try(&.as_i) || 0,
        passed_tests: data["passed"]?.try(&.as_i) || 0,
        failed_tests: data["failed"]?.try(&.as_i) || 0,
        skipped_tests: data["skipped"]?.try(&.as_i) || 0,
        error_message: nil,
        test_results: parse_test_results(data["tests"]?)
      )
    rescue ex : Exception
      ComplianceReport.new(
        success: false,
        exit_code: 1,
        total_tests: 0,
        passed_tests: 0,
        failed_tests: 0,
        skipped_tests: 0,
        error_message: "Failed to parse JSON results: #{ex.message}",
        test_results: [] of TestResult
      )
    end
  end

  private def parse_yaml_results(output : String) : ComplianceReport
    begin
      data = YAML.parse(output)
      
      ComplianceReport.new(
        success: true,
        exit_code: 0,
        total_tests: data["total"]?.try(&.as_i) || 0,
        passed_tests: data["passed"]?.try(&.as_i) || 0,
        failed_tests: data["failed"]?.try(&.as_i) || 0,
        skipped_tests: data["skipped"]?.try(&.as_i) || 0,
        error_message: nil,
        test_results: parse_test_results(data["tests"]?)
      )
    rescue ex : Exception
      ComplianceReport.new(
        success: false,
        exit_code: 1,
        total_tests: 0,
        passed_tests: 0,
        failed_tests: 0,
        skipped_tests: 0,
        error_message: "Failed to parse YAML results: #{ex.message}",
        test_results: [] of TestResult
      )
    end
  end

  private def parse_text_results(output : String) : ComplianceReport
    # Parse text output from h2spec
    lines = output.lines
    
    total_tests = 0
    passed_tests = 0
    failed_tests = 0
    skipped_tests = 0
    
    lines.each do |line|
      case line
      when /(\d+) tests, (\d+) passed, (\d+) failed, (\d+) skipped/
        total_tests = $1.to_i
        passed_tests = $2.to_i
        failed_tests = $3.to_i
        skipped_tests = $4.to_i
      end
    end
    
    ComplianceReport.new(
      success: failed_tests == 0,
      exit_code: failed_tests == 0 ? 0 : 1,
      total_tests: total_tests,
      passed_tests: passed_tests,
      failed_tests: failed_tests,
      skipped_tests: skipped_tests,
      error_message: nil,
      test_results: [] of TestResult
    )
  end

  private def parse_test_results(tests_data) : Array(TestResult)
    return [] of TestResult unless tests_data
    
    results = [] of TestResult
    
    case tests_data
    when Array
      tests_data.each do |test_data|
        results << TestResult.new(
          name: test_data["name"]?.try(&.as_s) || "Unknown",
          status: test_data["status"]?.try(&.as_s) || "unknown",
          description: test_data["description"]?.try(&.as_s),
          error_message: test_data["error"]?.try(&.as_s)
        )
      end
    end
    
    results
  end
end

# Compliance test result
class TestResult
  getter name : String
  getter status : String
  getter description : String?
  getter error_message : String?

  def initialize(@name, @status, @description = nil, @error_message = nil)
  end

  def passed? : Bool
    @status == "passed"
  end

  def failed? : Bool
    @status == "failed"
  end

  def skipped? : Bool
    @status == "skipped"
  end
end

# Compliance report
class ComplianceReport
  getter success : Bool
  getter exit_code : Int32
  getter total_tests : Int32
  getter passed_tests : Int32
  getter failed_tests : Int32
  getter skipped_tests : Int32
  getter error_message : String?
  getter test_results : Array(TestResult)
  getter timestamp : Time

  def initialize(@success, @exit_code, @total_tests, @passed_tests, @failed_tests, 
                 @skipped_tests, @error_message, @test_results)
    @timestamp = Time.utc
  end

  def compliance_percentage : Float64
    return 0.0 if @total_tests == 0
    (@passed_tests.to_f64 / @total_tests) * 100.0
  end

  def to_json : String
    {
      success: @success,
      exit_code: @exit_code,
      total_tests: @total_tests,
      passed_tests: @passed_tests,
      failed_tests: @failed_tests,
      skipped_tests: @skipped_tests,
      compliance_percentage: compliance_percentage,
      error_message: @error_message,
      timestamp: @timestamp.to_s,
      test_results: @test_results.map do |result|
        {
          name: result.name,
          status: result.status,
          description: result.description,
          error_message: result.error_message
        }
      end
    }.to_json
  end

  def to_yaml : String
    {
      success: @success,
      exit_code: @exit_code,
      total_tests: @total_tests,
      passed_tests: @passed_tests,
      failed_tests: @failed_tests,
      skipped_tests: @skipped_tests,
      compliance_percentage: compliance_percentage,
      error_message: @error_message,
      timestamp: @timestamp.to_s,
      test_results: @test_results.map do |result|
        {
          name: result.name,
          status: result.status,
          description: result.description,
          error_message: result.error_message
        }
      end
    }.to_yaml
  end

  def to_text : String
    io = IO::Memory.new
    
    io << "HTTP/2 Compliance Report\n"
    io << "=" * 50 << "\n"
    io << "Timestamp: #{@timestamp}\n"
    io << "Success: #{@success}\n"
    io << "Exit Code: #{@exit_code}\n"
    io << "Total Tests: #{@total_tests}\n"
    io << "Passed: #{@passed_tests}\n"
    io << "Failed: #{@failed_tests}\n"
    io << "Skipped: #{@skipped_tests}\n"
    io << "Compliance: #{compliance_percentage.round(2)}%\n"
    
    if @error_message
      io << "Error: #{@error_message}\n"
    end
    
    if @test_results.any?
      io << "\nTest Results:\n"
      io << "-" * 30 << "\n"
      
      @test_results.each do |result|
        status_icon = case result.status
        when "passed"
          "✓"
        when "failed"
          "✗"
        when "skipped"
          "-"
        else
          "?"
        end
        
        io << "#{status_icon} #{result.name}\n"
        
        if result.description
          io << "  Description: #{result.description}\n"
        end
        
        if result.error_message
          io << "  Error: #{result.error_message}\n"
        end
      end
    end
    
    io.to_s
  end
end

# Main execution
if __FILE__ == PROGRAM_NAME
  server_host = "localhost"
  server_port = 8080
  h2spec_path = "h2spec"
  output_format = "json"
  verbose = false
  timeout = 30
  output_file = nil
  test_categories = nil

  OptionParser.parse do |parser|
    parser.banner = "Usage: h2spec_runner [options]"

    parser.on("-h HOST", "--host=HOST", "Server host (default: localhost)") { |h| server_host = h }
    parser.on("-p PORT", "--port=PORT", "Server port (default: 8080)") { |p| server_port = p.to_i }
    parser.on("--h2spec-path=PATH", "Path to h2spec executable (default: h2spec)") { |path| h2spec_path = path }
    parser.on("-f FORMAT", "--format=FORMAT", "Output format: json, yaml, text (default: json)") { |f| output_format = f }
    parser.on("-v", "--verbose", "Verbose output") { verbose = true }
    parser.on("-t SECONDS", "--timeout=SECONDS", "Timeout in seconds (default: 30)") { |t| timeout = t.to_i }
    parser.on("-o FILE", "--output=FILE", "Output file") { |file| output_file = file }
    parser.on("--tests=CATEGORIES", "Comma-separated test categories") { |cats| test_categories = cats.split(",") }
    parser.on("--help", "Show this help") do
      puts parser
      exit
    end
  end

  begin
    runner = H2SpecRunner.new(server_host, server_port, h2spec_path, output_format, verbose, timeout)
    
    report = if test_categories
      runner.run_specific_tests(test_categories)
    else
      runner.run_tests
    end
    
    output = runner.generate_report(report)
    
    if output_file
      File.write(output_file, output)
      puts "Report written to #{output_file}"
    else
      puts output
    end
    
    exit report.success ? 0 : 1
  rescue ex : Exception
    STDERR.puts "Error: #{ex.message}"
    exit 1
  end
end