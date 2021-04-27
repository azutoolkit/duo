module Duo
  class Priority
    property exclusive : Bool
    property dep_stream_id : Int32
    property weight : Int32

    def initialize(@exclusive : Bool, @dep_stream_id : Int32, @weight : Int32)
    end
  end
end
