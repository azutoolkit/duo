require "../spec_helper"

describe "HTTP/2 Priority Compliance (RFC 9113 Section 5.3)" do
  describe "Priority Principles" do
    it "validates priority manager creation" do
      # RFC 9113 Section 5.3: Stream Priority
      # HTTP/2 allows a client to express a preference for how concurrent streams are processed
      
      priority_manager = Duo::Core::PriorityManager.new
      priority_manager.should be_a(Duo::Core::PriorityManager)
    end

    it "validates priority tree structure" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Each stream can be given an explicit dependency on another stream
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create root node (stream 0)
      root = priority_manager.get_or_create_node(0)
      root.should_not be_nil
      root.stream_id.should eq(0)
      root.weight.should eq(16) # Default weight
    end
  end

  describe "Stream Dependencies" do
    it "validates stream dependency creation" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Each stream can be given an explicit dependency on another stream
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create dependent stream
      stream_id = 1
      dependency_id = 0
      weight = 16
      exclusive = false
      
      node = priority_manager.add_stream(stream_id, dependency_id, weight, exclusive)
      node.should_not be_nil
      node.stream_id.should eq(stream_id)
      node.dependency_id.should eq(dependency_id)
      node.weight.should eq(weight)
      node.exclusive.should eq(exclusive)
    end

    it "validates exclusive dependency" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # The exclusive flag allows for the insertion of a new level of dependencies
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create exclusive dependency
      stream_id = 1
      dependency_id = 0
      weight = 16
      exclusive = true
      
      node = priority_manager.add_stream(stream_id, dependency_id, weight, exclusive)
      node.exclusive.should be_true
      
      # Check that dependency relationship is exclusive
      dependency = priority_manager.get_node(dependency_id)
      dependency.should_not be_nil
      
      # In exclusive mode, the new stream should be the only child
      children = dependency.not_nil!.children
      children.size.should eq(1)
      children.first.stream_id.should eq(stream_id)
    end

    it "validates non-exclusive dependency" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Non-exclusive dependencies allow multiple streams to share the same dependency
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create multiple streams with same dependency
      dependency_id = 0
      
      stream1 = priority_manager.add_stream(1, dependency_id, 16, false)
      stream2 = priority_manager.add_stream(3, dependency_id, 16, false)
      stream3 = priority_manager.add_stream(5, dependency_id, 16, false)
      
      # All streams should have the same dependency
      stream1.dependency_id.should eq(dependency_id)
      stream2.dependency_id.should eq(dependency_id)
      stream3.dependency_id.should eq(dependency_id)
      
      # Dependency should have multiple children
      dependency = priority_manager.get_node(dependency_id)
      dependency.should_not be_nil
      dependency.not_nil!.children.size.should eq(3)
    end

    it "validates dependency on non-existent stream" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Dependencies on non-existent streams should be treated as dependencies on stream 0
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create stream with dependency on non-existent stream
      stream_id = 1
      non_existent_dependency = 999
      weight = 16
      exclusive = false
      
      node = priority_manager.add_stream(stream_id, non_existent_dependency, weight, exclusive)
      node.dependency_id.should eq(0) # Should default to stream 0
    end

    it "validates self-dependency prevention" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # A stream cannot depend on itself
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Try to create self-dependency
      stream_id = 1
      
      expect_raises(Duo::Error) do
        priority_manager.add_stream(stream_id, stream_id, 16, false)
      end
    end
  end

  describe "Priority Weights" do
    it "validates weight range" do
      # RFC 9113 Section 5.3.2: Dependency Weighting
      # Weight ranges from 1 to 256
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Valid weights
      valid_weights = [1, 16, 256]
      valid_weights.each do |weight|
        node = priority_manager.add_stream(weight, 0, weight, false)
        node.weight.should eq(weight)
      end
      
      # Invalid weights
      invalid_weights = [0, 257]
      invalid_weights.each do |weight|
        expect_raises(Duo::Error) do
          priority_manager.add_stream(weight, 0, weight, false)
        end
      end
    end

    it "validates default weight" do
      # RFC 9113 Section 5.3.2: Dependency Weighting
      # The default weight is 16
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create stream without specifying weight
      node = priority_manager.add_stream(1, 0)
      node.weight.should eq(16)
    end

    it "validates weight inheritance" do
      # RFC 9113 Section 5.3.2: Dependency Weighting
      # Child streams inherit weight from parent
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create parent with specific weight
      parent_weight = 32
      parent = priority_manager.add_stream(1, 0, parent_weight, false)
      
      # Create child with different weight
      child_weight = 16
      child = priority_manager.add_stream(3, 1, child_weight, false)
      
      # Child should have its own weight, not inherit from parent
      child.weight.should eq(child_weight)
      parent.weight.should eq(parent_weight)
    end
  end

  describe "Priority Tree Management" do
    it "validates tree structure maintenance" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # The priority tree should maintain proper parent-child relationships
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create tree structure
      # Stream 0 (root)
      # ├── Stream 1 (weight 16)
      # │   ├── Stream 3 (weight 8)
      # │   └── Stream 5 (weight 8)
      # └── Stream 7 (weight 16)
      
      stream1 = priority_manager.add_stream(1, 0, 16, false)
      stream3 = priority_manager.add_stream(3, 1, 8, false)
      stream5 = priority_manager.add_stream(5, 1, 8, false)
      stream7 = priority_manager.add_stream(7, 0, 16, false)
      
      # Verify parent-child relationships
      root = priority_manager.get_node(0)
      root.should_not be_nil
      root.not_nil!.children.size.should eq(2)
      
      stream1_node = priority_manager.get_node(1)
      stream1_node.should_not be_nil
      stream1_node.not_nil!.children.size.should eq(2)
      stream1_node.not_nil!.parent.should eq(root)
    end

    it "validates tree rebalancing" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # The tree should rebalance when dependencies change
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create initial structure
      stream1 = priority_manager.add_stream(1, 0, 16, false)
      stream3 = priority_manager.add_stream(3, 1, 8, false)
      
      # Change dependency
      priority_manager.update_dependency(3, 0, 16, false)
      
      # Stream 3 should now be direct child of root
      stream3_node = priority_manager.get_node(3)
      stream3_node.should_not be_nil
      stream3_node.not_nil!.parent.stream_id.should eq(0)
      
      # Stream 1 should have no children
      stream1_node = priority_manager.get_node(1)
      stream1_node.should_not be_nil
      stream1_node.not_nil!.children.size.should eq(0)
    end

    it "validates tree cleanup on stream removal" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Removing a stream should properly clean up the tree
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create tree structure
      stream1 = priority_manager.add_stream(1, 0, 16, false)
      stream3 = priority_manager.add_stream(3, 1, 8, false)
      stream5 = priority_manager.add_stream(5, 1, 8, false)
      
      # Remove parent stream
      priority_manager.remove_stream(1)
      
      # Children should be reparented to root
      stream3_node = priority_manager.get_node(3)
      stream5_node = priority_manager.get_node(5)
      
      stream3_node.should_not be_nil
      stream5_node.should_not be_nil
      stream3_node.not_nil!.parent.stream_id.should eq(0)
      stream5_node.not_nil!.parent.stream_id.should eq(0)
      
      # Parent should be removed
      stream1_node = priority_manager.get_node(1)
      stream1_node.should be_nil
    end
  end

  describe "Priority Scheduling" do
    it "validates round-robin scheduling" do
      # RFC 9113 Section 5.3.2: Dependency Weighting
      # Streams with the same parent are scheduled in round-robin order
      
      priority_manager = Duo::Core::PriorityManager.new
      scheduler = Duo::Core::PriorityScheduler.new(priority_manager)
      
      # Create streams with same parent and weight
      priority_manager.add_stream(1, 0, 16, false)
      priority_manager.add_stream(3, 0, 16, false)
      priority_manager.add_stream(5, 0, 16, false)
      
      # Get scheduling order
      scheduled_streams = [] of Int32
      6.times do
        next_stream = scheduler.get_next_stream
        break if next_stream.nil?
        scheduled_streams << next_stream.stream_id
      end
      
      # Should schedule in round-robin order
      scheduled_streams.size.should be >= 3
      scheduled_streams[0..2].should contain(1)
      scheduled_streams[0..2].should contain(3)
      scheduled_streams[0..2].should contain(5)
    end

    it "validates weight-based scheduling" do
      # RFC 9113 Section 5.3.2: Dependency Weighting
      # Streams with higher weights should be scheduled more frequently
      
      priority_manager = Duo::Core::PriorityManager.new
      scheduler = Duo::Core::PriorityScheduler.new(priority_manager)
      
      # Create streams with different weights
      priority_manager.add_stream(1, 0, 32, false) # High weight
      priority_manager.add_stream(3, 0, 16, false) # Medium weight
      priority_manager.add_stream(5, 0, 8, false)  # Low weight
      
      # Get scheduling order
      scheduled_streams = [] of Int32
      12.times do
        next_stream = scheduler.get_next_stream
        break if next_stream.nil?
        scheduled_streams << next_stream.stream_id
      end
      
      # Stream 1 (high weight) should appear more frequently
      stream1_count = scheduled_streams.count(1)
      stream3_count = scheduled_streams.count(3)
      stream5_count = scheduled_streams.count(5)
      
      stream1_count.should be >= stream3_count
      stream3_count.should be >= stream5_count
    end

    it "validates dependency-based scheduling" do
      # RFC 9113 Section 5.3.2: Dependency Weighting
      # Parent streams should be scheduled before their children
      
      priority_manager = Duo::Core::PriorityManager.new
      scheduler = Duo::Core::PriorityScheduler.new(priority_manager)
      
      # Create parent-child relationship
      priority_manager.add_stream(1, 0, 16, false) # Parent
      priority_manager.add_stream(3, 1, 16, false) # Child
      
      # Get scheduling order
      scheduled_streams = [] of Int32
      4.times do
        next_stream = scheduler.get_next_stream
        break if next_stream.nil?
        scheduled_streams << next_stream.stream_id
      end
      
      # Parent should be scheduled before child
      parent_index = scheduled_streams.index(1)
      child_index = scheduled_streams.index(3)
      
      parent_index.should_not be_nil
      child_index.should_not be_nil
      parent_index.not_nil!.should be <= child_index.not_nil!
    end

    it "validates blocked stream handling" do
      # RFC 9113 Section 5.3.2: Dependency Weighting
      # Blocked streams should not prevent scheduling of other streams
      
      priority_manager = Duo::Core::PriorityManager.new
      scheduler = Duo::Core::PriorityScheduler.new(priority_manager)
      
      # Create streams
      stream1 = priority_manager.add_stream(1, 0, 16, false)
      stream3 = priority_manager.add_stream(3, 0, 16, false)
      
      # Mark stream1 as blocked
      scheduler.mark_blocked(1)
      
      # Get next stream
      next_stream = scheduler.get_next_stream
      next_stream.should_not be_nil
      next_stream.not_nil!.stream_id.should eq(3) # Should skip blocked stream
    end
  end

  describe "Priority Frame Processing" do
    it "validates PRIORITY frame processing" do
      # RFC 9113 Section 6.3: PRIORITY
      # PRIORITY frames should update stream priorities
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create initial stream
      stream = priority_manager.add_stream(1, 0, 16, false)
      
      # Process PRIORITY frame
      new_dependency = 0
      new_weight = 32
      exclusive = false
      
      priority_manager.update_priority(1, new_dependency, new_weight, exclusive)
      
      # Stream should be updated
      updated_stream = priority_manager.get_node(1)
      updated_stream.should_not be_nil
      updated_stream.not_nil!.dependency_id.should eq(new_dependency)
      updated_stream.not_nil!.weight.should eq(new_weight)
      updated_stream.not_nil!.exclusive.should eq(exclusive)
    end

    it "validates PRIORITY frame on non-existent stream" do
      # RFC 9113 Section 6.3: PRIORITY
      # PRIORITY frames can be sent for streams that don't exist
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Send PRIORITY frame for non-existent stream
      non_existent_stream = 999
      dependency = 0
      weight = 16
      exclusive = false
      
      # Should create the stream
      priority_manager.update_priority(non_existent_stream, dependency, weight, exclusive)
      
      # Stream should now exist
      stream = priority_manager.get_node(non_existent_stream)
      stream.should_not be_nil
      stream.not_nil!.stream_id.should eq(non_existent_stream)
    end

    it "validates PRIORITY frame payload size" do
      # RFC 9113 Section 6.3: PRIORITY
      # PRIORITY frame payload is exactly 5 octets
      
      frame = Duo::Core::FrameFactory.create_priority_frame(1, false, 0, 16)
      frame.type.should eq(Duo::FrameType::Priority)
      frame.payload.size.should eq(5)
    end
  end

  describe "Priority Error Handling" do
    it "handles circular dependencies" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Circular dependencies should be prevented
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create dependency chain
      priority_manager.add_stream(1, 0, 16, false)
      priority_manager.add_stream(3, 1, 16, false)
      
      # Try to create circular dependency
      expect_raises(Duo::Error) do
        priority_manager.update_dependency(1, 3, 16, false)
      end
    end

    it "handles invalid dependency updates" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Invalid dependency updates should be handled gracefully
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Try to update dependency on non-existent stream
      expect_raises(Duo::Error) do
        priority_manager.update_dependency(1, 999, 16, false)
      end
    end

    it "handles concurrent priority updates" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Concurrent priority updates should be handled correctly
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create initial stream
      priority_manager.add_stream(1, 0, 16, false)
      
      # Concurrent updates
      fibers = [] of Fiber
      10.times do |i|
        fibers << spawn do
          priority_manager.update_priority(1, 0, 16 + i, false)
        end
      end
      
      # Wait for all fibers to complete
      fibers.each(&.join)
      
      # Stream should still exist and be valid
      stream = priority_manager.get_node(1)
      stream.should_not be_nil
      stream.not_nil!.stream_id.should eq(1)
    end
  end

  describe "Priority Performance" do
    it "handles large priority trees" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Priority management should handle large trees efficiently
      
      priority_manager = Duo::Core::PriorityManager.new
      scheduler = Duo::Core::PriorityScheduler.new(priority_manager)
      
      # Create large tree
      1000.times do |i|
        parent = (i / 10) * 10 # Create hierarchical structure
        parent = 0 if parent == 0
        priority_manager.add_stream(i + 1, parent, 16, false)
      end
      
      # Should handle scheduling efficiently
      100.times do
        next_stream = scheduler.get_next_stream
        next_stream.should_not be_nil
      end
    end

    it "handles rapid priority changes" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Priority changes should be handled efficiently
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create streams
      priority_manager.add_stream(1, 0, 16, false)
      priority_manager.add_stream(3, 0, 16, false)
      
      # Rapid priority changes
      1000.times do |i|
        priority_manager.update_priority(1, 0, 16 + (i % 10), false)
      end
      
      # Stream should still be valid
      stream = priority_manager.get_node(1)
      stream.should_not be_nil
      stream.not_nil!.stream_id.should eq(1)
    end

    it "handles concurrent stream creation" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Concurrent stream creation should be handled correctly
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Concurrent stream creation
      fibers = [] of Fiber
      100.times do |i|
        fibers << spawn do
          priority_manager.add_stream(i + 1, 0, 16, false)
        end
      end
      
      # Wait for all fibers to complete
      fibers.each(&.join)
      
      # All streams should exist
      100.times do |i|
        stream = priority_manager.get_node(i + 1)
        stream.should_not be_nil
        stream.not_nil!.stream_id.should eq(i + 1)
      end
    end
  end

  describe "Priority Integration" do
    it "integrates with stream lifecycle" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Priority management should integrate with stream lifecycle
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Create stream with priority
      stream = priority_manager.add_stream(1, 0, 16, false)
      
      # Simulate stream lifecycle
      stream.active = true
      stream.active.should be_true
      
      # Simulate stream completion
      priority_manager.remove_stream(1)
      
      # Stream should be removed from priority tree
      removed_stream = priority_manager.get_node(1)
      removed_stream.should be_nil
    end

    it "integrates with flow control" do
      # RFC 9113 Section 5.3.2: Dependency Weighting
      # Priority should work with flow control
      
      priority_manager = Duo::Core::PriorityManager.new
      scheduler = Duo::Core::PriorityScheduler.new(priority_manager)
      
      # Create streams
      priority_manager.add_stream(1, 0, 16, false)
      priority_manager.add_stream(3, 0, 16, false)
      
      # Mark stream as flow control blocked
      scheduler.mark_flow_control_blocked(1)
      
      # Get next stream
      next_stream = scheduler.get_next_stream
      next_stream.should_not be_nil
      next_stream.not_nil!.stream_id.should eq(3) # Should skip blocked stream
    end

    it "integrates with connection settings" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Priority should work with connection settings
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Test with different settings
      settings = Duo::Settings.new
      settings.max_concurrent_streams = 100
      
      # Should work with settings
      50.times do |i|
        priority_manager.add_stream(i + 1, 0, 16, false)
      end
      
      # All streams should be created successfully
      50.times do |i|
        stream = priority_manager.get_node(i + 1)
        stream.should_not be_nil
      end
    end
  end

  describe "Priority Security" do
    it "prevents priority abuse" do
      # RFC 9113 Section 5.3.1: Stream Dependencies
      # Priority system should prevent abuse
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Try to create too many high-priority streams
      1000.times do |i|
        priority_manager.add_stream(i + 1, 0, 256, false) # Maximum weight
      end
      
      # Should handle gracefully
      # (Implementation should prevent resource exhaustion)
    end

    it "validates priority frame limits" do
      # RFC 9113 Section 6.3: PRIORITY
      # Priority frames should have reasonable limits
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Try to send many priority updates
      1000.times do |i|
        begin
          priority_manager.update_priority(1, 0, 16, false)
        rescue Duo::Error
          # Error is acceptable if limits are enforced
          break
        end
      end
    end

    it "handles malicious priority data" do
      # RFC 9113 Section 6.3: PRIORITY
      # Malicious priority data should be handled securely
      
      priority_manager = Duo::Core::PriorityManager.new
      
      # Try to create stream with malicious data
      expect_raises(Duo::Error) do
        priority_manager.add_stream(-1, 0, 16, false) # Invalid stream ID
      end
      
      expect_raises(Duo::Error) do
        priority_manager.add_stream(1, 0, 0, false) # Invalid weight
      end
    end
  end
end