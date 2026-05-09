import Darwin
import Foundation

struct ForegroundProcess: Equatable, Sendable {
  let pid: pid_t
  let name: String
  let argv0: String?
  let cmdline: String?
}

struct ForegroundJob: Equatable, Sendable {
  let processGroupID: pid_t
  let processes: [ForegroundProcess]
}

enum ProcessDetection {
  static func foregroundJob(childPID: pid_t) -> ForegroundJob? {
    guard childPID > 0, let processGroupID = foregroundProcessGroupID(pid: childPID) else {
      return nil
    }

    var pids = [pid_t](repeating: 0, count: 4096)
    let bytes = pids.withUnsafeMutableBufferPointer { buffer in
      proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
    }
    guard bytes > 0 else { return nil }

    let count = Int(bytes) / MemoryLayout<pid_t>.size
    let processes = pids.prefix(count).compactMap { pid -> ForegroundProcess? in
      guard pid > 0,
        let info = processBSDInfo(pid: pid),
        pid_t(info.pbi_pgid) == processGroupID,
        let name = comm(from: info)
      else {
        return nil
      }
      return ForegroundProcess(
        pid: pid,
        name: name,
        argv0: processArgv0Name(pid: pid),
        cmdline: processCommandLine(pid: pid)
      )
    }

    guard !processes.isEmpty else { return nil }
    return ForegroundJob(processGroupID: processGroupID, processes: processes)
  }

  static func foregroundProcessGroupID(pid: pid_t) -> pid_t? {
    guard let info = processBSDInfo(pid: pid), info.e_tpgid > 0 else {
      return nil
    }
    return pid_t(info.e_tpgid)
  }

  static func processCommandLine(pid: pid_t) -> String? {
    guard let buffer = kernProcargs2(pid: pid), let argv = procargs2Argv(buffer), !argv.isEmpty else {
      return nil
    }
    return argv.joined(separator: " ")
  }

  static func processArgv0Name(pid: pid_t) -> String? {
    guard let buffer = kernProcargs2(pid: pid), let argv0 = procargs2Argv(buffer)?.first else {
      return nil
    }
    return basename(argv0)
  }

  static func processBSDInfo(pid: pid_t) -> proc_bsdinfo? {
    var info = proc_bsdinfo()
    let size = MemoryLayout<proc_bsdinfo>.size
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, Int32(size))
    }
    return result == Int32(size) ? info : nil
  }

  static func comm(from info: proc_bsdinfo) -> String? {
    let bytes = withUnsafeBytes(of: info.pbi_comm) { rawBuffer -> [UInt8] in
      Array(rawBuffer)
    }
    let end = bytes.firstIndex(of: 0) ?? bytes.count
    guard end > 0 else { return nil }
    return String(bytes: bytes[..<end], encoding: .utf8)
  }

  static func kernProcargs2(pid: pid_t) -> [UInt8]? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
      return nil
    }

    var buffer = [UInt8](repeating: 0, count: size)
    let result = buffer.withUnsafeMutableBufferPointer { pointer in
      sysctl(&mib, u_int(mib.count), pointer.baseAddress, &size, nil, 0)
    }
    guard result == 0 else { return nil }
    return Array(buffer.prefix(size))
  }

  static func procargs2Argv(_ buffer: [UInt8]) -> [String]? {
    guard buffer.count >= MemoryLayout<Int32>.size else { return nil }
    let argc = buffer.withUnsafeBytes { rawBuffer in
      rawBuffer.load(as: Int32.self)
    }
    guard argc > 0 else { return nil }

    var position = MemoryLayout<Int32>.size
    guard let execEnd = buffer[position...].firstIndex(of: 0) else { return nil }
    position = execEnd
    while position < buffer.count, buffer[position] == 0 {
      position += 1
    }

    var argv: [String] = []
    while position < buffer.count, argv.count < Int(argc) {
      let start = position
      while position < buffer.count, buffer[position] != 0 {
        position += 1
      }
      if position > start, let value = String(bytes: buffer[start..<position], encoding: .utf8) {
        argv.append(value)
      }
      while position < buffer.count, buffer[position] == 0 {
        position += 1
      }
    }

    return argv.isEmpty ? nil : argv
  }

  static func basename(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    guard !trimmed.isEmpty else { return nil }
    let name = (trimmed as NSString).lastPathComponent
    let stripped = name.hasPrefix("-") ? String(name.dropFirst()) : name
    return stripped.isEmpty ? nil : stripped
  }
}
