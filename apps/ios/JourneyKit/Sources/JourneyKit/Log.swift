import os

public enum Log {
    public static let subsystem = "fm.journey.app"
    public static let session = Logger(subsystem: subsystem, category: "session")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let art = Logger(subsystem: subsystem, category: "art")
}
