module Duo
  module Core
    # Performance monitoring and optimization utilities
    class PerformanceMonitor
      private getter metrics : Hash(String, Metric)
      private getter mutex : Mutex
      private getter enabled : Bool

      def initialize(@enabled = true)
        @metrics = {} of String => Metric
        @mutex = Mutex.new
      end

      # Records a timing measurement
      def record_timing(name : String, duration : Time::Span) : Nil
        return unless @enabled

        @mutex.synchronize do
          metric = @metrics[name]? || Metric.new(name)
          metric.add_timing(duration)
          @metrics[name] = metric
        end
      end

      # Records a counter increment
      def increment_counter(name : String, value : Int32 = 1) : Nil
        return unless @enabled

        @mutex.synchronize do
          metric = @metrics[name]? || Metric.new(name)
          metric.increment_counter(value)
          @metrics[name] = metric
        end
      end

      # Records a gauge value
      def set_gauge(name : String, value : Float64) : Nil
        return unless @enabled

        @mutex.synchronize do
          metric = @metrics[name]? || Metric.new(name)
          metric.set_gauge(value)
          @metrics[name] = metric
        end
      end

      # Gets performance report
      def get_report : PerformanceReport
        @mutex.synchronize do
          PerformanceReport.new(@metrics.values.dup)
        end
      end

      # Clears all metrics
      def clear : Nil
        @mutex.synchronize do
          @metrics.clear
        end
      end

      # Measures execution time of a block
      def measure(name : String, &block) : T forall T
        start_time = Time.monotonic
        result = yield
        end_time = Time.monotonic
        
        record_timing(name, end_time - start_time)
        result
      end
    end

    # Individual metric tracking
    class Metric
      getter name : String
      getter timings : Array(Time::Span)
      getter counter : Int64
      getter gauge : Float64?
      getter min_timing : Time::Span?
      getter max_timing : Time::Span?

      def initialize(@name)
        @timings = [] of Time::Span
        @counter = 0_i64
        @gauge = nil
        @min_timing = nil
        @max_timing = nil
      end

      def add_timing(duration : Time::Span) : Nil
        @timings << duration
        
        @min_timing = duration if @min_timing.nil? || duration < @min_timing
        @max_timing = duration if @max_timing.nil? || duration > @max_timing
      end

      def increment_counter(value : Int32) : Nil
        @counter += value
      end

      def set_gauge(value : Float64) : Nil
        @gauge = value
      end

      def average_timing : Time::Span?
        return nil if @timings.empty?
        
        total_nanoseconds = @timings.sum(&.total_nanoseconds)
        Time::Span.new(nanoseconds: total_nanoseconds // @timings.size)
      end

      def timing_count : Int32
        @timings.size
      end

      def p95_timing : Time::Span?
        return nil if @timings.empty?
        
        sorted = @timings.sort
        index = (sorted.size * 0.95).to_i
        sorted[index]
      end

      def p99_timing : Time::Span?
        return nil if @timings.empty?
        
        sorted = @timings.sort
        index = (sorted.size * 0.99).to_i
        sorted[index]
      end
    end

    # Performance report
    class PerformanceReport
      getter metrics : Array(Metric)
      getter timestamp : Time

      def initialize(@metrics)
        @timestamp = Time.utc
      end

      def to_s : String
        io = IO::Memory.new
        io << "Performance Report (#{@timestamp})\n"
        io << "=" * 50 << "\n\n"

        @metrics.each do |metric|
          io << "Metric: #{metric.name}\n"
          
          if metric.timing_count > 0
            io << "  Timings: #{metric.timing_count} samples\n"
            io << "  Average: #{metric.average_timing}\n"
            io << "  Min: #{metric.min_timing}\n"
            io << "  Max: #{metric.max_timing}\n"
            io << "  P95: #{metric.p95_timing}\n"
            io << "  P99: #{metric.p99_timing}\n"
          end
          
          if metric.counter > 0
            io << "  Counter: #{metric.counter}\n"
          end
          
          if metric.gauge
            io << "  Gauge: #{metric.gauge}\n"
          end
          
          io << "\n"
        end

        io.to_s
      end
    end

    # Benchmark utilities
    class Benchmark
      private getter iterations : Int32
      private getter warmup_iterations : Int32

      def initialize(@iterations = 1000, @warmup_iterations = 100)
      end

      # Runs a benchmark and returns results
      def run(name : String, &block) : BenchmarkResult
        # Warmup phase
        @warmup_iterations.times { yield }

        # Actual benchmark
        start_time = Time.monotonic
        @iterations.times { yield }
        end_time = Time.monotonic

        total_time = end_time - start_time
        average_time = total_time / @iterations

        BenchmarkResult.new(name, @iterations, total_time, average_time)
      end

      # Compares multiple implementations
      def compare(implementations : Hash(String, Proc(Nil)), &block) : Array(BenchmarkResult)
        results = [] of BenchmarkResult

        implementations.each do |name, implementation|
          result = run(name) { implementation.call }
          results << result
          yield result if block_given?
        end

        results.sort_by(&.average_time)
      end
    end

    # Benchmark result
    struct BenchmarkResult
      getter name : String
      getter iterations : Int32
      getter total_time : Time::Span
      getter average_time : Time::Span

      def initialize(@name, @iterations, @total_time, @average_time)
      end

      def operations_per_second : Float64
        return 0.0 if @average_time.total_nanoseconds == 0
        1_000_000_000.0 / @average_time.total_nanoseconds
      end

      def to_s : String
        "#{@name}: #{@iterations} iterations in #{@total_time} (#{@average_time} avg, #{operations_per_second.round(2)} ops/sec)"
      end
    end

    # Concurrency optimizations
    class ConcurrencyOptimizer
      private getter fiber_pool : FiberPool
      private getter task_queue : Channel(Task)
      private getter max_concurrent_tasks : Int32

      def initialize(@max_concurrent_tasks = 100)
        @fiber_pool = FiberPool.new(@max_concurrent_tasks)
        @task_queue = Channel(Task).new(@max_concurrent_tasks * 2)
        spawn_task_processor
      end

      # Submits a task for execution
      def submit_task(name : String, &block) : Task
        task = Task.new(name, block)
        @task_queue.send(task)
        task
      end

      # Waits for all tasks to complete
      def wait_for_all : Nil
        @task_queue.close
        @fiber_pool.wait_for_all
      end

      # Gets current task statistics
      def stats : TaskStats
        @fiber_pool.stats
      end

      private def spawn_task_processor : Nil
        spawn do
          loop do
            begin
              task = @task_queue.receive
              @fiber_pool.execute { task.execute }
            rescue Channel::ClosedError
              break
            end
          end
        end
      end
    end

    # Fiber pool for efficient concurrency
    class FiberPool
      private getter fibers : Array(Fiber)
      private getter task_queue : Channel(Proc(Nil))
      private getter max_fibers : Int32
      private getter active_fibers : Atomic(Int32)
      private getter completed_tasks : Atomic(Int64)

      def initialize(@max_fibers)
        @fibers = [] of Fiber
        @task_queue = Channel(Proc(Nil)).new(@max_fibers * 2)
        @active_fibers = Atomic(Int32).new(0)
        @completed_tasks = Atomic(Int64).new(0)
        
        spawn_fibers
      end

      # Executes a task in the pool
      def execute(&task : -> Nil) : Nil
        @task_queue.send(task)
      end

      # Waits for all fibers to complete
      def wait_for_all : Nil
        @task_queue.close
        @fibers.each(&.join)
      end

      # Gets pool statistics
      def stats : TaskStats
        TaskStats.new(
          max_fibers: @max_fibers,
          active_fibers: @active_fibers.get,
          completed_tasks: @completed_tasks.get
        )
      end

      private def spawn_fibers : Nil
        @max_fibers.times do
          fiber = spawn do
            loop do
              begin
                task = @task_queue.receive
                @active_fibers.add(1)
                task.call
                @completed_tasks.add(1)
                @active_fibers.sub(1)
              rescue Channel::ClosedError
                break
              end
            end
          end
          @fibers << fiber
        end
      end
    end

    # Task representation
    class Task
      getter name : String
      getter status : TaskStatus
      getter result : TaskResult?
      getter error : Exception?

      private getter block : Proc(Nil)
      private getter start_time : Time?
      private getter end_time : Time?

      def initialize(@name, @block)
        @status = TaskStatus::Pending
      end

      def execute : Nil
        @status = TaskStatus::Running
        @start_time = Time.monotonic

        begin
          @block.call
          @result = TaskResult::Success
        rescue ex : Exception
          @error = ex
          @result = TaskResult::Error
        ensure
          @end_time = Time.monotonic
          @status = TaskStatus::Completed
        end
      end

      def duration : Time::Span?
        return nil unless @start_time && @end_time
        @end_time.not_nil! - @start_time.not_nil!
      end

      def success? : Bool
        @result == TaskResult::Success
      end
    end

    # Task status enum
    enum TaskStatus
      Pending
      Running
      Completed
    end

    # Task result enum
    enum TaskResult
      Success
      Error
    end

    # Task statistics
    struct TaskStats
      getter max_fibers : Int32
      getter active_fibers : Int32
      getter completed_tasks : Int64

      def initialize(@max_fibers, @active_fibers, @completed_tasks)
      end

      def utilization : Float64
        return 0.0 if @max_fibers == 0
        @active_fibers.to_f64 / @max_fibers
      end
    end

    # IO optimization utilities
    class IOOptimizer
      private getter buffer_pool : BufferPool
      private getter read_buffers : Hash(IO, Bytes)
      private getter write_buffers : Hash(IO, Bytes)
      private getter mutex : Mutex

      def initialize
        @buffer_pool = BufferPool.new
        @read_buffers = {} of IO => Bytes
        @write_buffers = {} of IO => Bytes
        @mutex = Mutex.new
      end

      # Optimized read with buffer reuse
      def optimized_read(io : IO, size : Int32) : Bytes
        @mutex.synchronize do
          buffer = @read_buffers[io]? || @buffer_pool.get_buffer(size)
          
          if buffer.size < size
            buffer = @buffer_pool.get_buffer(size)
            @read_buffers[io] = buffer
          end

          result = buffer[0, size]
          io.read_fully(result)
          result
        end
      end

      # Optimized write with buffer reuse
      def optimized_write(io : IO, data : Bytes) : Nil
        @mutex.synchronize do
          buffer = @write_buffers[io]? || @buffer_pool.get_buffer(data.size)
          
          if buffer.size < data.size
            buffer = @buffer_pool.get_buffer(data.size)
            @write_buffers[io] = buffer
          end

          buffer[0, data.size].copy_from(data)
          io.write(buffer[0, data.size])
        end
      end

      # Cleans up buffers for a specific IO
      def cleanup_io(io : IO) : Nil
        @mutex.synchronize do
          if buffer = @read_buffers.delete(io)
            @buffer_pool.return_buffer(buffer)
          end
          
          if buffer = @write_buffers.delete(io)
            @buffer_pool.return_buffer(buffer)
          end
        end
      end

      # Gets buffer usage statistics
      def buffer_stats : Hash(IO, Int32)
        @mutex.synchronize do
          stats = {} of IO => Int32
          
          @read_buffers.each do |io, buffer|
            stats[io] = buffer.size
          end
          
          @write_buffers.each do |io, buffer|
            stats[io] = (stats[io]? || 0) + buffer.size
          end
          
          stats
        end
      end
    end

    # Profiling utilities
    class Profiler
      private getter samples : Array(Sample)
      private getter mutex : Mutex
      private getter enabled : Bool
      private getter sample_interval : Time::Span

      def initialize(@enabled = false, @sample_interval = 10.milliseconds)
        @samples = [] of Sample
        @mutex = Mutex.new
      end

      # Starts profiling
      def start : Nil
        return unless @enabled
        
        spawn do
          loop do
            sample = Sample.new(Time.monotonic, GC.stats)
            @mutex.synchronize do
              @samples << sample
            end
            sleep @sample_interval
          end
        end
      end

      # Gets profiling report
      def get_report : ProfilingReport
        @mutex.synchronize do
          ProfilingReport.new(@samples.dup)
        end
      end

      # Clears all samples
      def clear : Nil
        @mutex.synchronize do
          @samples.clear
        end
      end
    end

    # Profiling sample
    struct Sample
      getter timestamp : Time::Monotonic
      getter gc_stats : GC::Stats

      def initialize(@timestamp, @gc_stats)
      end
    end

    # Profiling report
    class ProfilingReport
      getter samples : Array(Sample)
      getter timestamp : Time

      def initialize(@samples)
        @timestamp = Time.utc
      end

      def duration : Time::Span
        return Time::Span.zero if @samples.size < 2
        @samples.last.timestamp - @samples.first.timestamp
      end

      def average_memory_usage : Int64
        return 0_i64 if @samples.empty?
        total = @samples.sum(&.gc_stats.heap_size)
        total // @samples.size
      end

      def peak_memory_usage : Int64
        return 0_i64 if @samples.empty?
        @samples.max_of(&.gc_stats.heap_size)
      end

      def gc_collections : Int32
        return 0 if @samples.empty?
        @samples.last.gc_stats.collections - @samples.first.gc_stats.collections
      end

      def to_s : String
        io = IO::Memory.new
        io << "Profiling Report (#{@timestamp})\n"
        io << "=" * 50 << "\n"
        io << "Duration: #{duration}\n"
        io << "Samples: #{@samples.size}\n"
        io << "Average Memory: #{average_memory_usage} bytes\n"
        io << "Peak Memory: #{peak_memory_usage} bytes\n"
        io << "GC Collections: #{gc_collections}\n"
        io.to_s
      end
    end
  end
end