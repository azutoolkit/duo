module Duo
  enum FrameType
    Data         = 0x0
    Headers      = 0x1
    Priority     = 0x2
    RstStream    = 0x3
    Settings     = 0x4
    PushPromise  = 0x5
    Ping         = 0x6
    GoAway       = 0x7
    WindowUpdate = 0x8
    Continuation = 0x9

    def self.non_transitional?(type)
      [Priority, GoAway, Ping].includes?(type)
    end

    def self.skip?(type)
      [GoAway, WindowUpdate, Continuation].includes?(type)
    end
  end
end
