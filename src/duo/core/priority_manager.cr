module Duo
  module Core
    # Manages HTTP/2 stream prioritization according to RFC 9113 Section 5.3
    class PriorityManager
      private getter dependency_tree : Hash(Int32, PriorityNode)
      private getter mutex : Mutex
      private getter scheduler : PriorityScheduler

      def initialize
        @dependency_tree = {} of Int32 => PriorityNode
        @mutex = Mutex.new
        @scheduler = PriorityScheduler.new
      end

      # Updates stream priority
      def update_priority(stream_id : Int32, exclusive : Bool, dependency_stream_id : Int32, weight : Int32)
        @mutex.synchronize do
          validate_priority_update(stream_id, dependency_stream_id, weight)
          
          # Remove stream from old parent
          remove_from_parent(stream_id)
          
          # Update dependency
          if dependency_stream_id == 0
            # Root dependency
            add_to_root(stream_id, weight)
          else
            # Specific dependency
            add_to_dependency(stream_id, dependency_stream_id, exclusive, weight)
          end
          
          # Update scheduler
          @scheduler.update_stream_priority(stream_id, get_effective_weight(stream_id))
        end
      end

      # Removes a stream from priority management
      def remove_stream(stream_id : Int32)
        @mutex.synchronize do
          if node = @dependency_tree[stream_id]?
            # Remove from parent
            remove_from_parent(stream_id)
            
            # Reparent children to parent
            reparent_children(stream_id)
            
            # Remove from tree
            @dependency_tree.delete(stream_id)
            
            # Update scheduler
            @scheduler.remove_stream(stream_id)
          end
        end
      end

      # Gets the next stream to process based on priority
      def next_stream_to_process : Int32?
        @mutex.synchronize do
          @scheduler.next_stream
        end
      end

      # Gets all streams ready for processing, ordered by priority
      def streams_ready_for_processing : Array(Int32)
        @mutex.synchronize do
          @scheduler.ready_streams
        end
      end

      # Marks a stream as blocked (e.g., waiting for flow control)
      def block_stream(stream_id : Int32)
        @mutex.synchronize do
          @scheduler.block_stream(stream_id)
        end
      end

      # Marks a stream as unblocked
      def unblock_stream(stream_id : Int32)
        @mutex.synchronize do
          @scheduler.unblock_stream(stream_id)
        end
      end

      # Gets the effective weight of a stream
      def effective_weight(stream_id : Int32) : Int32
        @mutex.synchronize do
          get_effective_weight(stream_id)
        end
      end

      # Gets the dependency tree for debugging
      def dependency_tree_debug : String
        @mutex.synchronize do
          build_debug_tree
        end
      end

      private def validate_priority_update(stream_id : Int32, dependency_stream_id : Int32, weight : Int32)
        # Stream cannot depend on itself
        if stream_id == dependency_stream_id
          raise Error.protocol_error("Stream cannot depend on itself")
        end
        
        # Weight must be between 1 and 256
        unless 1 <= weight <= 256
          raise Error.protocol_error("Priority weight must be between 1 and 256")
        end
        
        # Check for circular dependencies
        if would_create_circular_dependency?(stream_id, dependency_stream_id)
          raise Error.protocol_error("Circular dependency detected")
        end
      end

      private def would_create_circular_dependency?(stream_id : Int32, dependency_stream_id : Int32) : Bool
        return false if dependency_stream_id == 0
        
        # Check if dependency_stream_id is a descendant of stream_id
        current = dependency_stream_id
        visited = Set(Int32).new
        
        while current != 0 && !visited.includes?(current)
          visited << current
          if node = @dependency_tree[current]?
            current = node.parent_id
          else
            break
          end
        end
        
        visited.includes?(stream_id)
      end

      private def remove_from_parent(stream_id : Int32)
        if node = @dependency_tree[stream_id]?
          if parent = @dependency_tree[node.parent_id]?
            parent.children.delete(stream_id)
          end
        end
      end

      private def add_to_root(stream_id : Int32, weight : Int32)
        node = PriorityNode.new(stream_id, 0, weight, false)
        @dependency_tree[stream_id] = node
      end

      private def add_to_dependency(stream_id : Int32, dependency_stream_id : Int32, exclusive : Bool, weight : Int32)
        # Ensure dependency exists
        unless @dependency_tree[dependency_stream_id]?
          # Create dependency node if it doesn't exist
          @dependency_tree[dependency_stream_id] = PriorityNode.new(dependency_stream_id, 0, 16, false)
        end
        
        dependency_node = @dependency_tree[dependency_stream_id]
        
        if exclusive
          # Move all children of dependency to the new stream
          children_to_move = dependency_node.children.dup
          children_to_move.each do |child_id|
            if child_node = @dependency_tree[child_id]?
              child_node.parent_id = stream_id
              dependency_node.children.delete(child_id)
            end
          end
          
          # Create new stream node
          new_node = PriorityNode.new(stream_id, dependency_stream_id, weight, false)
          new_node.children = children_to_move
          @dependency_tree[stream_id] = new_node
        else
          # Add as regular child
          new_node = PriorityNode.new(stream_id, dependency_stream_id, weight, false)
          @dependency_tree[stream_id] = new_node
        end
        
        # Add to parent's children
        dependency_node.children << stream_id
      end

      private def reparent_children(stream_id : Int32)
        if node = @dependency_tree[stream_id]?
          parent_id = node.parent_id
          
          node.children.each do |child_id|
            if child_node = @dependency_tree[child_id]?
              child_node.parent_id = parent_id
              
              if parent_id == 0
                # Child becomes root-level
              else
                # Add child to parent's children
                if parent = @dependency_tree[parent_id]?
                  parent.children << child_id
                end
              end
            end
          end
        end
      end

      private def get_effective_weight(stream_id : Int32) : Int32
        if node = @dependency_tree[stream_id]?
          # Calculate effective weight based on dependency chain
          effective_weight = node.weight
          current = node.parent_id
          
          while current != 0
            if parent = @dependency_tree[current]?
              effective_weight = (effective_weight * parent.weight) // 256
              current = parent.parent_id
            else
              break
            end
          end
          
          effective_weight
        else
          16 # Default weight
        end
      end

      private def build_debug_tree : String
        io = IO::Memory.new
        io << "Priority Tree:\n"
        
        # Find root nodes (parent_id == 0)
        root_nodes = @dependency_tree.values.select { |node| node.parent_id == 0 }
        
        root_nodes.each do |root|
          print_node(io, root, 0)
        end
        
        io.to_s
      end

      private def print_node(io : IO::Memory, node : PriorityNode, depth : Int32)
        indent = "  " * depth
        io << "#{indent}Stream #{node.id} (weight: #{node.weight}, effective: #{get_effective_weight(node.id)})\n"
        
        node.children.each do |child_id|
          if child = @dependency_tree[child_id]?
            print_node(io, child, depth + 1)
          end
        end
      end
    end

    # Represents a node in the priority dependency tree
    class PriorityNode
      getter id : Int32
      property parent_id : Int32
      property weight : Int32
      property exclusive : Bool
      getter children : Array(Int32)

      def initialize(@id, @parent_id, @weight, @exclusive)
        @children = [] of Int32
      end
    end

    # Schedules streams based on priority weights
    class PriorityScheduler
      private getter ready_streams : Array(Int32)
      private getter blocked_streams : Set(Int32)
      private getter stream_weights : Hash(Int32, Int32)
      private getter mutex : Mutex

      def initialize
        @ready_streams = [] of Int32
        @blocked_streams = Set(Int32).new
        @stream_weights = {} of Int32 => Int32
        @mutex = Mutex.new
      end

      def update_stream_priority(stream_id : Int32, weight : Int32)
        @mutex.synchronize do
          @stream_weights[stream_id] = weight
          
          unless @blocked_streams.includes?(stream_id)
            add_to_ready_streams(stream_id)
          end
        end
      end

      def remove_stream(stream_id : Int32)
        @mutex.synchronize do
          @ready_streams.delete(stream_id)
          @blocked_streams.delete(stream_id)
          @stream_weights.delete(stream_id)
        end
      end

      def block_stream(stream_id : Int32)
        @mutex.synchronize do
          @ready_streams.delete(stream_id)
          @blocked_streams.add(stream_id)
        end
      end

      def unblock_stream(stream_id : Int32)
        @mutex.synchronize do
          @blocked_streams.delete(stream_id)
          add_to_ready_streams(stream_id)
        end
      end

      def next_stream : Int32?
        @mutex.synchronize do
          @ready_streams.shift?
        end
      end

      def ready_streams : Array(Int32)
        @mutex.synchronize do
          @ready_streams.dup
        end
      end

      private def add_to_ready_streams(stream_id : Int32)
        return if @ready_streams.includes?(stream_id)
        
        weight = @stream_weights[stream_id]? || 16
        
        # Insert based on weight (higher weight = higher priority)
        insert_index = @ready_streams.index { |id| (@stream_weights[id]? || 16) < weight } || @ready_streams.size
        @ready_streams.insert(insert_index, stream_id)
      end
    end
  end
end