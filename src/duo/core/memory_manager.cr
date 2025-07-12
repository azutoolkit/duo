module Duo
  module Core
    # Memory management utilities to prevent leaks and optimize performance
    class MemoryManager
      private getter frame_pool : ObjectPool(Core::Frame)
      private getter buffer_pool : ObjectPool(Bytes)
      private getter headers_pool : ObjectPool(HTTP::Headers)
      private getter mutex : Mutex
      private getter allocated_buffers : Set(Pointer(UInt8))
      private getter max_pool_size : Int32

      def initialize(@max_pool_size = 1000)
        @frame_pool = ObjectPool(Core::Frame).new(@max_pool_size)
        @buffer_pool = ObjectPool(Bytes).new(@max_pool_size)
        @headers_pool = ObjectPool(HTTP::Headers).new(@max_pool_size)
        @mutex = Mutex.new
        @allocated_buffers = Set(Pointer(UInt8)).new
      end

      # Gets a frame from the pool or creates a new one
      def get_frame : Core::Frame
        @frame_pool.get { Core::Frame.new(FrameType::Data, 0, Frame::Flags::None, Bytes.new) }
      end

      # Returns a frame to the pool
      def return_frame(frame : Core::Frame) : Nil
        # Reset frame state
        frame.reset if frame.responds_to?(:reset)
        @frame_pool.return(frame)
      end

      # Gets a buffer from the pool or creates a new one
      def get_buffer(size : Int32) : Bytes
        @buffer_pool.get { Bytes.new(size) }
      end

      # Returns a buffer to the pool
      def return_buffer(buffer : Bytes) : Nil
        @buffer_pool.return(buffer)
      end

      # Gets headers from the pool or creates new ones
      def get_headers : HTTP::Headers
        @headers_pool.get { HTTP::Headers.new }
      end

      # Returns headers to the pool
      def return_headers(headers : HTTP::Headers) : Nil
        headers.clear
        @headers_pool.return(headers)
      end

      # Allocates a buffer with tracking
      def allocate_buffer(size : Int32) : Bytes
        @mutex.synchronize do
          buffer = GC.malloc_atomic(size).as(UInt8*)
          @allocated_buffers.add(buffer)
          buffer.to_slice(size)
        end
      end

      # Frees a tracked buffer
      def free_buffer(buffer : Bytes) : Nil
        @mutex.synchronize do
          pointer = buffer.to_unsafe
          if @allocated_buffers.delete(pointer)
            GC.free(pointer)
          end
        end
      end

      # Gets memory usage statistics
      def memory_stats : MemoryStats
        @mutex.synchronize do
          MemoryStats.new(
            frame_pool_size: @frame_pool.size,
            buffer_pool_size: @buffer_pool.size,
            headers_pool_size: @headers_pool.size,
            allocated_buffers_count: @allocated_buffers.size,
            max_pool_size: @max_pool_size
          )
        end
      end

      # Cleans up all allocated memory
      def cleanup : Nil
        @mutex.synchronize do
          # Free all tracked buffers
          @allocated_buffers.each do |pointer|
            GC.free(pointer)
          end
          @allocated_buffers.clear

          # Clear pools
          @frame_pool.clear
          @buffer_pool.clear
          @headers_pool.clear
        end
      end

      # Checks for memory leaks
      def check_for_leaks : Array(String)
        leaks = [] of String

        @mutex.synchronize do
          if @allocated_buffers.size > 0
            leaks << "#{@allocated_buffers.size} allocated buffers not freed"
          end

          if @frame_pool.size > @max_pool_size * 2
            leaks << "Frame pool size (#{@frame_pool.size}) exceeds reasonable limit"
          end

          if @buffer_pool.size > @max_pool_size * 2
            leaks << "Buffer pool size (#{@buffer_pool.size}) exceeds reasonable limit"
          end

          if @headers_pool.size > @max_pool_size * 2
            leaks << "Headers pool size (#{@headers_pool.size}) exceeds reasonable limit"
          end
        end

        leaks
      end
    end

    # Generic object pool for reusing objects
    class ObjectPool(T)
      private getter pool : Array(T)
      private getter mutex : Mutex
      private getter max_size : Int32
      private getter factory : Proc(T)?

      def initialize(@max_size = 1000, @factory = nil)
        @pool = [] of T
        @mutex = Mutex.new
      end

      # Gets an object from the pool or creates a new one
      def get(&factory : -> T) : T
        @mutex.synchronize do
          if @pool.empty?
            factory.call
          else
            @pool.pop
          end
        end
      end

      # Returns an object to the pool
      def return(obj : T) : Nil
        @mutex.synchronize do
          if @pool.size < @max_size
            @pool << obj
          end
        end
      end

      # Gets the current pool size
      def size : Int32
        @mutex.synchronize do
          @pool.size
        end
      end

      # Clears the pool
      def clear : Nil
        @mutex.synchronize do
          @pool.clear
        end
      end
    end

    # Memory usage statistics
    struct MemoryStats
      getter frame_pool_size : Int32
      getter buffer_pool_size : Int32
      getter headers_pool_size : Int32
      getter allocated_buffers_count : Int32
      getter max_pool_size : Int32

      def initialize(@frame_pool_size, @buffer_pool_size, @headers_pool_size, @allocated_buffers_count, @max_pool_size)
      end

      def total_pooled_objects : Int32
        @frame_pool_size + @buffer_pool_size + @headers_pool_size
      end

      def pool_utilization : Float64
        return 0.0 if @max_pool_size == 0
        total_pooled_objects.to_f64 / (@max_pool_size * 3)
      end
    end

    # Buffer pool for efficient memory management
    class BufferPool
      private getter pools : Hash(Int32, ObjectPool(Bytes))
      private getter mutex : Mutex
      private getter max_pool_size : Int32

      def initialize(@max_pool_size = 100)
        @pools = {} of Int32 => ObjectPool(Bytes)
        @mutex = Mutex.new
      end

      # Gets a buffer of the specified size
      def get_buffer(size : Int32) : Bytes
        @mutex.synchronize do
          pool = @pools[size]? || create_pool(size)
          pool.get { Bytes.new(size) }
        end
      end

      # Returns a buffer to the appropriate pool
      def return_buffer(buffer : Bytes) : Nil
        @mutex.synchronize do
          if pool = @pools[buffer.size]?
            pool.return(buffer)
          end
        end
      end

      # Gets statistics for all pools
      def stats : Hash(Int32, Int32)
        @mutex.synchronize do
          @pools.transform_values(&.size)
        end
      end

      # Clears all pools
      def clear : Nil
        @mutex.synchronize do
          @pools.values.each(&.clear)
        end
      end

      private def create_pool(size : Int32) : ObjectPool(Bytes)
        pool = ObjectPool(Bytes).new(@max_pool_size)
        @pools[size] = pool
        pool
      end
    end

    # Circular buffer with automatic memory management
    class ManagedCircularBuffer < IO
      private getter buffer : Pointer(UInt8)
      private getter capacity : Int32
      private getter read_offset : Int32
      private getter write_offset : Int32
      private getter size : Int32
      private getter closed : Bool

      def initialize(@capacity : Int32)
        @buffer = GC.malloc_atomic(@capacity).as(UInt8*)
        @read_offset = 0
        @write_offset = 0
        @size = 0
        @closed = false
      end

      def read(slice : Bytes) : Int32
        return 0 if @closed && @size == 0

        bytes_to_read = Math.min(slice.size, @size)
        return 0 if bytes_to_read == 0

        # Copy data from buffer to slice
        if @read_offset + bytes_to_read <= @capacity
          # Single copy
          @buffer.to_slice(@read_offset, bytes_to_read).copy_to(slice)
        else
          # Wrap around copy
          first_part = @capacity - @read_offset
          @buffer.to_slice(@read_offset, first_part).copy_to(slice)
          @buffer.to_slice(0, bytes_to_read - first_part).copy_to(slice + first_part)
        end

        @read_offset = (@read_offset + bytes_to_read) % @capacity
        @size -= bytes_to_read

        bytes_to_read
      end

      def write(slice : Bytes) : Nil
        raise IO::Error.new("Buffer is closed") if @closed

        slice.each_byte do |byte|
          while @size >= @capacity
            # Buffer is full, wait for space
            Fiber.yield
          end

          @buffer[@write_offset] = byte
          @write_offset = (@write_offset + 1) % @capacity
          @size += 1
        end
      end

      def close : Nil
        @closed = true
      end

      def closed? : Bool
        @closed
      end

      def available_bytes : Int32
        @size
      end

      def free_bytes : Int32
        @capacity - @size
      end

      def full? : Bool
        @size >= @capacity
      end

      def empty? : Bool
        @size == 0
      end

      def finalize
        GC.free(@buffer)
      end
    end

    # Memory leak detector
    class MemoryLeakDetector
      private getter allocations : Hash(String, Array(AllocationInfo))
      private getter mutex : Mutex
      private getter enabled : Bool

      def initialize(@enabled = false)
        @allocations = {} of String => Array(AllocationInfo)
        @mutex = Mutex.new
      end

      # Tracks an allocation
      def track_allocation(type : String, size : Int32, stack_trace : String? = nil) : String
        return "" unless @enabled

        id = generate_id
        info = AllocationInfo.new(id, type, size, stack_trace)

        @mutex.synchronize do
          @allocations[type] ||= [] of AllocationInfo
          @allocations[type] << info
        end

        id
      end

      # Marks an allocation as freed
      def free_allocation(id : String) : Nil
        return unless @enabled

        @mutex.synchronize do
          @allocations.each do |type, allocations|
            allocations.reject! { |info| info.id == id }
          end
        end
      end

      # Gets leak report
      def get_leak_report : LeakReport
        @mutex.synchronize do
          leaks = [] of LeakInfo

          @allocations.each do |type, allocations|
            next if allocations.empty?

            total_size = allocations.sum(&.size)
            leaks << LeakInfo.new(type, allocations.size, total_size, allocations.dup)
          end

          LeakReport.new(leaks)
        end
      end

      # Clears all tracking
      def clear : Nil
        @mutex.synchronize do
          @allocations.clear
        end
      end

      private def generate_id : String
        Random::Secure.hex(8)
      end
    end

    # Allocation tracking information
    struct AllocationInfo
      getter id : String
      getter type : String
      getter size : Int32
      getter stack_trace : String?
      getter timestamp : Time

      def initialize(@id, @type, @size, @stack_trace)
        @timestamp = Time.utc
      end
    end

    # Leak information
    struct LeakInfo
      getter type : String
      getter count : Int32
      getter total_size : Int32
      getter allocations : Array(AllocationInfo)

      def initialize(@type, @count, @total_size, @allocations)
      end
    end

    # Leak report
    struct LeakReport
      getter leaks : Array(LeakInfo)
      getter timestamp : Time

      def initialize(@leaks)
        @timestamp = Time.utc
      end

      def total_leaks : Int32
        @leaks.sum(&.count)
      end

      def total_size : Int32
        @leaks.sum(&.total_size)
      end

      def has_leaks? : Bool
        !@leaks.empty?
      end
    end
  end
end