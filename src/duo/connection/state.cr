module Duo
  enum State
    Idle
    ReservedLocal
    ReservedRemote
    Open
    HalfClosedLocal
    HalfClosedRemote
    Closed

    def active?
      self == Open ||
        self == HalfClosedLocal ||
        self == HalfClosedRemote
    end

    # :nodoc:
    def to_s(io)
      io << "#{self}"
    end
  end
end
