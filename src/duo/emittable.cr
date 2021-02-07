module Duo
  module Emittable
    macro included
      @channel = Channel(Frame | Array(Frame) | Nil).new(10)
    end

    def frame_writer
      loop do
        begin
          case frame = @channel.receive
          when Array(Frame) then frame.each { |f| write(f, flush: false) }
          when Frame then write(frame, flush: false)
          else
            io.close unless io.closed?
            break
          end
        rescue Channel::ClosedError
          break
        ensure
          io.flush if @channel.@queue.not_nil!.empty?
        end
      end
    end

    def send(frame : Frame)
      @channel.send(frame) unless @channel.closed?
    end

    def send(frame : Array(Frame))
      @channel.send(frame) unless @channel.closed?
    end

    def close_channel!
      unless @channel.closed?
        @channel.send(nil)
        @channel.close
      end
    end
  end
end