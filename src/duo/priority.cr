module Duo
  class Priority
    property exclusive : Bool
    property dep_stream_id : Int32
    property weight : Int32

    def initialize(@exclusive : Bool, @dep_stream_id : Int32, @weight : Int32)
    end

    # :nodoc:
    def debug
      "exclusive=#{exclusive} dep_stream_id=#{dep_stream_id} weight=#{weight}"
    end
  end
end
