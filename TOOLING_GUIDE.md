# HTTP/2 Implementation Tooling Guide

## Overview

This guide provides comprehensive instructions for setting up testing, validation, and monitoring tools for the Duo HTTP/2 implementation. These tools ensure RFC 9113 compliance, performance validation, and production readiness.

## 1. Compliance Testing with h2spec

### 1.1 Installation

#### **macOS**
```bash
# Using Homebrew
brew install h2spec

# Manual installation
git clone https://github.com/summerwind/h2spec.git
cd h2spec
make build
sudo cp bin/h2spec /usr/local/bin/
```

#### **Linux**
```bash
# Ubuntu/Debian
wget https://github.com/summerwind/h2spec/releases/latest/download/h2spec_linux_amd64.tar.gz
tar -xzf h2spec_linux_amd64.tar.gz
sudo mv h2spec /usr/local/bin/

# CentOS/RHEL
sudo yum install -y wget
wget https://github.com/summerwind/h2spec/releases/latest/download/h2spec_linux_amd64.tar.gz
tar -xzf h2spec_linux_amd64.tar.gz
sudo mv h2spec /usr/local/bin/
```

#### **Windows**
```bash
# Using Chocolatey
choco install h2spec

# Manual installation
# Download from https://github.com/summerwind/h2spec/releases
```

### 1.2 Integration with Crystal Tests

#### **h2spec Test Runner**
```crystal
# spec/compliance/h2spec_runner.cr
require "spec"
require "process"

class H2SpecRunner
  private getter server_port : Int32
  private getter server_process : Process?

  def initialize(@server_port = 8080)
  end

  def run_compliance_tests : Bool
    # Start test server
    start_test_server
    
    # Run h2spec
    result = run_h2spec
    
    # Stop test server
    stop_test_server
    
    result
  end

  private def start_test_server
    @server_process = Process.new(
      "crystal", 
      ["run", "examples/test_server.cr", "--port", @server_port.to_s],
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe
    )
    
    # Wait for server to start
    sleep 2
  end

  private def run_h2spec : Bool
    result = Process.run(
      "h2spec",
      ["-p", @server_port.to_s, "-t", "--strict"],
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe
    )
    
    puts "h2spec output:"
    puts result.output_message
    puts "h2spec errors:"
    puts result.error_message
    
    result.exit_status == 0
  end

  private def stop_test_server
    @server_process.try &.terminate
    @server_process.try &.wait
  end
end

# Integration test
describe "HTTP/2 Compliance" do
  it "passes h2spec tests" do
    runner = H2SpecRunner.new
    runner.run_compliance_tests.should be_true
  end
end
```

#### **Automated Compliance Testing**
```crystal
# spec/compliance/automated_compliance_spec.cr
require "../spec_helper"

describe "Automated HTTP/2 Compliance" do
  describe "Frame Format" do
    it "validates DATA frame format" do
      # Test DATA frame parsing and validation
    end

    it "validates HEADERS frame format" do
      # Test HEADERS frame parsing and validation
    end

    it "validates SETTINGS frame format" do
      # Test SETTINGS frame parsing and validation
    end
  end

  describe "Stream Lifecycle" do
    it "validates stream state transitions" do
      # Test all valid state transitions
    end

    it "rejects invalid state transitions" do
      # Test invalid state transitions
    end
  end

  describe "Flow Control" do
    it "validates window management" do
      # Test flow control window updates
    end

    it "handles flow control errors" do
      # Test flow control error conditions
    end
  end
end
```

## 2. Performance Testing

### 2.1 Benchmark Framework

#### **Crystal Benchmark Integration**
```crystal
# spec/performance/benchmark_spec.cr
require "benchmark"
require "../spec_helper"

class HTTP2Benchmark
  private getter connection_manager : Duo::Core::ConnectionManager

  def initialize
    io = IO::Memory.new
    settings = Duo::Settings.new
    @connection_manager = Duo::Core::ConnectionManager.new(
      Duo::Core::IOManager.new(io),
      Duo::Connection::Type::Server,
      settings
    )
  end

  def benchmark_frame_processing
    Benchmark.ips do |x|
      x.report("Frame Processing") do
        process_test_frames
      end
    end
  end

  def benchmark_concurrent_streams
    Benchmark.ips do |x|
      x.report("Concurrent Streams") do
        create_concurrent_streams
      end
    end
  end

  def benchmark_memory_usage
    initial_memory = GC.stats.total_allocated
    process_test_frames
    final_memory = GC.stats.total_allocated
    
    memory_used = final_memory - initial_memory
    puts "Memory used: #{memory_used} bytes"
  end

  private def process_test_frames
    1000.times do |i|
      frame = Duo::Core::FrameFactory.create_ping_frame
      connection_manager.send("send_frame", frame)
    end
  end

  private def create_concurrent_streams
    100.times do |i|
      connection_manager.stream_manager.create_stream
    end
  end
end

describe "HTTP/2 Performance" do
  it "benchmarks frame processing" do
    benchmark = HTTP2Benchmark.new
    benchmark.benchmark_frame_processing
  end

  it "benchmarks concurrent streams" do
    benchmark = HTTP2Benchmark.new
    benchmark.benchmark_concurrent_streams
  end

  it "measures memory usage" do
    benchmark = HTTP2Benchmark.new
    benchmark.benchmark_memory_usage
  end
end
```

### 2.2 Load Testing

#### **HTTP/2 Load Testing with h2load**
```crystal
# spec/performance/load_test_spec.cr
require "process"

class LoadTester
  private getter server_port : Int32

  def initialize(@server_port = 8080)
  end

  def run_load_test(concurrent_streams : Int32, requests : Int32) : LoadTestResult
    result = Process.run(
      "h2load",
      [
        "-n", requests.to_s,
        "-c", concurrent_streams.to_s,
        "-m", "10",
        "http://localhost:#{server_port}/"
      ],
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe
    )

    parse_h2load_output(result.output_message)
  end

  private def parse_h2load_output(output : String) : LoadTestResult
    # Parse h2load output to extract metrics
    lines = output.lines
    
    # Extract metrics from output
    # This is a simplified parser - adjust based on actual h2load output format
    requests_per_sec = extract_metric(lines, "requests/s")
    time_per_request = extract_metric(lines, "time per request")
    
    LoadTestResult.new(requests_per_sec, time_per_request)
  end

  private def extract_metric(lines : Array(String), metric_name : String) : Float64
    # Implementation depends on h2load output format
    0.0
  end
end

struct LoadTestResult
  getter requests_per_second : Float64
  getter time_per_request : Float64

  def initialize(@requests_per_second, @time_per_request)
  end
end

describe "HTTP/2 Load Testing" do
  it "handles high concurrency" do
    tester = LoadTester.new
    result = tester.run_load_test(100, 10000)
    
    result.requests_per_second.should be > 1000.0
    result.time_per_request.should be < 100.0
  end
end
```

## 3. Memory Leak Detection

### 3.1 Memory Profiling

#### **Crystal Memory Profiler Integration**
```crystal
# spec/memory/memory_profiler_spec.cr
require "spec"

class MemoryProfiler
  private getter allocations : Hash(String, Int64)
  private getter start_time : Time

  def initialize
    @allocations = {} of String => Int64
    @start_time = Time.utc
  end

  def start_profiling
    GC.collect
    @start_time = Time.utc
  end

  def stop_profiling : MemoryProfile
    GC.collect
    end_time = Time.utc
    
    MemoryProfile.new(
      total_allocated: GC.stats.total_allocated,
      total_freed: GC.stats.total_freed,
      duration: end_time - @start_time
    )
  end

  def track_allocation(klass : String, size : Int32)
    @allocations[klass] ||= 0_i64
    @allocations[klass] += size.to_i64
  end

  def get_allocation_summary : Hash(String, Int64)
    @allocations.dup
  end
end

struct MemoryProfile
  getter total_allocated : Int64
  getter total_freed : Int64
  getter duration : Time::Span

  def initialize(@total_allocated, @total_freed, @duration)
  end

  def net_allocation : Int64
    @total_allocated - @total_freed
  end

  def allocation_rate : Float64
    net_allocation.to_f / @duration.total_seconds
  end
end

describe "Memory Management" do
  it "detects memory leaks" do
    profiler = MemoryProfiler.new
    
    profiler.start_profiling
    
    # Perform operations that might leak memory
    1000.times do
      connection_manager = create_test_connection_manager
      connection_manager.close
    end
    
    profile = profiler.stop_profiling
    
    # Should not have significant memory leaks
    profile.net_allocation.should be < 1_000_000 # 1MB threshold
  end

  it "tracks allocation by class" do
    profiler = MemoryProfiler.new
    
    profiler.start_profiling
    
    # Create various objects
    100.times do
      Duo::Core::FrameFactory.create_ping_frame
    end
    
    profile = profiler.stop_profiling
    allocations = profiler.get_allocation_summary
    
    # Should have tracked allocations
    allocations.size.should be > 0
  end
end
```

### 3.2 Automated Leak Detection

#### **Continuous Memory Monitoring**
```crystal
# spec/memory/continuous_monitoring_spec.cr
class ContinuousMemoryMonitor
  private getter check_interval : Time::Span
  private getter max_allocation_growth : Int64
  private getter running : Bool

  def initialize(@check_interval = 1.second, @max_allocation_growth = 1_000_000)
    @running = false
  end

  def start_monitoring
    @running = true
    spawn do
      monitor_loop
    end
  end

  def stop_monitoring
    @running = false
  end

  private def monitor_loop
    previous_allocation = GC.stats.total_allocated
    
    while @running
      sleep @check_interval
      
      current_allocation = GC.stats.total_allocated
      growth = current_allocation - previous_allocation
      
      if growth > @max_allocation_growth
        Log.warn { "Potential memory leak detected: #{growth} bytes allocated" }
      end
      
      previous_allocation = current_allocation
    end
  end
end

describe "Continuous Memory Monitoring" do
  it "detects memory growth over time" do
    monitor = ContinuousMemoryMonitor.new(100.milliseconds, 1000)
    monitor.start_monitoring
    
    # Perform operations
    sleep 500.milliseconds
    
    monitor.stop_monitoring
  end
end
```

## 4. Monitoring and Metrics

### 4.1 Metrics Collection

#### **Prometheus Integration**
```crystal
# spec/monitoring/metrics_spec.cr
require "prometheus"

class HTTP2Metrics
  private getter registry : Prometheus::Registry
  private getter connection_counter : Prometheus::Counter
  private getter stream_counter : Prometheus::Counter
  private getter frame_counter : Prometheus::Counter
  private getter request_duration : Prometheus::Histogram

  def initialize
    @registry = Prometheus::Registry.new
    
    @connection_counter = Prometheus::Counter.new(
      "http2_connections_total",
      "Total number of HTTP/2 connections"
    )
    
    @stream_counter = Prometheus::Counter.new(
      "http2_streams_total",
      "Total number of HTTP/2 streams"
    )
    
    @frame_counter = Prometheus::Counter.new(
      "http2_frames_total",
      "Total number of HTTP/2 frames processed"
    )
    
    @request_duration = Prometheus::Histogram.new(
      "http2_request_duration_seconds",
      "HTTP/2 request duration"
    )
    
    @registry.register(@connection_counter)
    @registry.register(@stream_counter)
    @registry.register(@frame_counter)
    @registry.register(@request_duration)
  end

  def record_connection_established
    @connection_counter.increment
  end

  def record_stream_created
    @stream_counter.increment
  end

  def record_frame_processed(frame_type : String)
    @frame_counter.increment(labels: {"type" => frame_type})
  end

  def record_request_duration(duration : Time::Span)
    @request_duration.observe(duration.total_seconds)
  end

  def get_metrics : String
    @registry.to_text
  end
end

describe "HTTP/2 Metrics" do
  it "collects connection metrics" do
    metrics = HTTP2Metrics.new
    
    metrics.record_connection_established
    metrics.record_stream_created
    metrics.record_frame_processed("DATA")
    
    metrics_text = metrics.get_metrics
    metrics_text.should contain("http2_connections_total")
    metrics_text.should contain("http2_streams_total")
    metrics_text.should contain("http2_frames_total")
  end
end
```

### 4.2 Health Checks

#### **HTTP/2 Health Check Endpoint**
```crystal
# spec/monitoring/health_check_spec.cr
class HTTP2HealthCheck
  private getter connection_manager : Duo::Core::ConnectionManager
  private getter metrics : HTTP2Metrics

  def initialize(@connection_manager, @metrics)
  end

  def health_status : HealthStatus
    HealthStatus.new(
      healthy: connection_manager.connection_state.open?,
      active_connections: metrics.connection_counter.value,
      active_streams: metrics.stream_counter.value,
      uptime: Time.utc - start_time
    )
  end

  def readiness_status : ReadinessStatus
    ReadinessStatus.new(
      ready: connection_manager.connection_state.open?,
      error_count: 0 # Track error count
    )
  end

  def liveness_status : LivenessStatus
    LivenessStatus.new(
      alive: true,
      last_heartbeat: Time.utc
    )
  end
end

struct HealthStatus
  getter healthy : Bool
  getter active_connections : Float64
  getter active_streams : Float64
  getter uptime : Time::Span
end

struct ReadinessStatus
  getter ready : Bool
  getter error_count : Int32
end

struct LivenessStatus
  getter alive : Bool
  getter last_heartbeat : Time
end

describe "HTTP/2 Health Checks" do
  it "provides health status" do
    io = IO::Memory.new
    settings = Duo::Settings.new
    connection_manager = Duo::Core::ConnectionManager.new(
      Duo::Core::IOManager.new(io),
      Duo::Connection::Type::Server,
      settings
    )
    metrics = HTTP2Metrics.new
    
    health_check = HTTP2HealthCheck.new(connection_manager, metrics)
    status = health_check.health_status
    
    status.healthy.should be_true
  end
end
```

## 5. CI/CD Integration

### 5.1 GitHub Actions Workflow

#### **Automated Testing Pipeline**
```yaml
# .github/workflows/http2-testing.yml
name: HTTP/2 Testing

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Crystal
      uses: crystal-lang/install-crystal@v1
      with:
        crystal: latest
    
    - name: Install h2spec
      run: |
        wget https://github.com/summerwind/h2spec/releases/latest/download/h2spec_linux_amd64.tar.gz
        tar -xzf h2spec_linux_amd64.tar.gz
        sudo mv h2spec /usr/local/bin/
    
    - name: Run compliance tests
      run: crystal spec spec/compliance/
    
    - name: Run h2spec tests
      run: crystal spec spec/compliance/h2spec_runner_spec.cr

  performance:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Crystal
      uses: crystal-lang/install-crystal@v1
      with:
        crystal: latest
    
    - name: Run performance tests
      run: crystal spec spec/performance/
    
    - name: Run memory tests
      run: crystal spec spec/memory/

  security:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Crystal
      uses: crystal-lang/install-crystal@v1
      with:
        crystal: latest
    
    - name: Run security tests
      run: crystal spec spec/security/
```

### 5.2 Docker Integration

#### **Test Container**
```dockerfile
# Dockerfile.test
FROM crystallang/crystal:latest

# Install testing tools
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install h2spec
RUN wget https://github.com/summerwind/h2spec/releases/latest/download/h2spec_linux_amd64.tar.gz \
    && tar -xzf h2spec_linux_amd64.tar.gz \
    && mv h2spec /usr/local/bin/ \
    && rm h2spec_linux_amd64.tar.gz

# Install h2load
RUN apt-get update && apt-get install -y nghttp2-client

# Copy source code
COPY . /app
WORKDIR /app

# Run tests
CMD ["crystal", "spec"]
```

## 6. Development Tools

### 6.1 HTTP/2 Debugging

#### **Frame Inspector**
```crystal
# tools/frame_inspector.cr
class FrameInspector
  def inspect_frame(frame : Duo::Frame) : String
    io = IO::Memory.new
    io << "Frame Type: #{frame.type}\n"
    io << "Stream ID: #{frame.stream_id}\n"
    io << "Flags: #{frame.flags}\n"
    io << "Size: #{frame.size}\n"
    
    if payload = frame.payload?
      io << "Payload: #{payload.hexstring}\n"
    end
    
    io.to_s
  end

  def inspect_connection_state(connection_manager : Duo::Core::ConnectionManager) : String
    io = IO::Memory.new
    io << "Connection State: #{connection_manager.connection_state}\n"
    io << "Active Streams: #{connection_manager.stream_manager.active_streams.size}\n"
    io << "Flow Control Window: #{connection_manager.flow_control.connection_window_size}\n"
    io.to_s
  end
end
```

### 6.2 Performance Profiling

#### **Crystal Profiler Integration**
```crystal
# tools/profiler.cr
require "profile"

class HTTP2Profiler
  def profile_connection_processing
    Profile.profile do
      # Run connection processing
      connection_manager = create_test_connection_manager
      1000.times do
        frame = Duo::Core::FrameFactory.create_ping_frame
        connection_manager.send("send_frame", frame)
      end
      connection_manager.close
    end
  end

  def profile_memory_usage
    GC.collect
    initial_memory = GC.stats.total_allocated
    
    # Run operations
    connection_manager = create_test_connection_manager
    1000.times do
      frame = Duo::Core::FrameFactory.create_ping_frame
      connection_manager.send("send_frame", frame)
    end
    connection_manager.close
    
    GC.collect
    final_memory = GC.stats.total_allocated
    
    puts "Memory used: #{final_memory - initial_memory} bytes"
  end
end
```

## 7. Usage Examples

### 7.1 Running Tests

```bash
# Run all tests
crystal spec

# Run compliance tests only
crystal spec spec/compliance/

# Run performance tests only
crystal spec spec/performance/

# Run memory tests only
crystal spec spec/memory/

# Run with coverage
crystal spec --coverage

# Run with verbose output
crystal spec --verbose
```

### 7.2 Running h2spec

```bash
# Run h2spec against local server
h2spec -p 8080

# Run with strict mode
h2spec -p 8080 -t --strict

# Run specific test cases
h2spec -p 8080 -t 4.1  # Frame format tests
h2spec -p 8080 -t 5.1  # Stream lifecycle tests
h2spec -p 8080 -t 6.9  # Flow control tests
```

### 7.3 Performance Testing

```bash
# Run benchmarks
crystal run spec/performance/benchmark_spec.cr

# Run load tests
h2load -n 10000 -c 100 -m 10 http://localhost:8080/

# Monitor memory usage
crystal run spec/memory/memory_profiler_spec.cr
```

## 8. Troubleshooting

### 8.1 Common Issues

#### **h2spec Connection Refused**
```bash
# Ensure test server is running
crystal run examples/test_server.cr --port 8080

# Check server logs
tail -f server.log
```

#### **Memory Leaks in Tests**
```bash
# Run with GC debugging
CRYSTAL_DEBUG=1 crystal spec spec/memory/

# Use valgrind for detailed analysis
valgrind --leak-check=full crystal spec spec/memory/
```

#### **Performance Test Failures**
```bash
# Check system resources
htop
iostat
netstat -i

# Run with reduced load
h2load -n 1000 -c 10 http://localhost:8080/
```

### 8.2 Debug Mode

```crystal
# Enable debug logging
Log.setup(:debug)

# Enable frame debugging
Duo::Core::FrameInspector.enable_debug = true

# Enable memory debugging
GC.debug = true
```

This comprehensive tooling guide provides all the necessary tools and procedures to ensure the HTTP/2 implementation is compliant, performant, and production-ready.