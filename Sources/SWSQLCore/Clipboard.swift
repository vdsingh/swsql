import Foundation

/// Puts text on the system clipboard from inside a full-screen terminal app.
///
/// Two mechanisms, tried in order:
///
/// 1. A native clipboard tool (`pbcopy`, `wl-copy`, `xclip`, `xsel`) when the
///    session looks like it has one, because a local tool always works.
/// 2. The OSC 52 escape sequence, written to the controlling terminal. This is
///    what works over SSH: the terminal emulator on the local machine receives
///    the sequence and sets the local clipboard. Not every terminal honours it
///    (Terminal.app does not), but the terminals that cannot are the same ones
///    that cannot remap ⌘, so the native tools carry them.
///
/// The tools are spawned with `posix_spawnp`, not `Foundation.Process`: this
/// is called from inside the UI's input handler, and `Process.waitUntilExit`
/// spins the run loop, which re-enters the input handling mid-keystroke.
public enum Clipboard {
    /// The OSC 52 sequence asking the terminal to set the system clipboard.
    public static func osc52(for text: String) -> String {
        "\u{1b}]52;c;\(Data(text.utf8).base64EncodedString())\u{07}"
    }

    /// Copies `text` to the system clipboard. Returns nil on success, or a
    /// description of why nothing could be copied.
    public static func copy(_ text: String) -> String? {
        // A clipboard tool that exits without reading its input (or a missing
        // one) must not take the whole app down with SIGPIPE; the short write
        // already reports the failure.
        signal(SIGPIPE, SIG_IGN)
        for tool in tools where run(tool, input: text) {
            return nil
        }
        return sendOSC52(text)
    }

    /// The clipboard commands worth trying in this session, in preference
    /// order. Each is only listed when its display server (or OS) is actually
    /// present, so absent tools are not spawned on every copy.
    private static var tools: [[String]] {
        var tools: [[String]] = []
        #if os(macOS)
        tools.append(["pbcopy"])
        #endif
        let environment = ProcessInfo.processInfo.environment
        if environment["WAYLAND_DISPLAY"] != nil {
            tools.append(["wl-copy"])
        }
        if environment["DISPLAY"] != nil {
            tools.append(["xclip", "-selection", "clipboard"])
            tools.append(["xsel", "--input", "--clipboard"])
        }
        return tools
    }

    /// Runs a clipboard tool with `input` on stdin. False when the tool is
    /// missing or failed, which just moves the search along.
    private static func run(_ arguments: [String], input: String) -> Bool {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return false }

        // The child reads the pipe as stdin and talks to no terminal.
        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t?
        #else
        var actions = posix_spawn_file_actions_t()
        #endif
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, fds[0], 0)
        posix_spawn_file_actions_addclose(&actions, fds[1])
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

        var argv = arguments.map { strdup($0) }
        argv.append(nil)
        var envp = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        var pid: pid_t = 0
        let spawned = posix_spawnp(&pid, arguments[0], &actions, nil, argv, envp)
        posix_spawn_file_actions_destroy(&actions)
        argv.forEach { free($0) }
        envp.forEach { free($0) }
        close(fds[0])
        guard spawned == 0 else {
            close(fds[1])
            return false
        }

        let bytes = Array(input.utf8)
        var offset = 0
        var wroteEverything = true
        bytes.withUnsafeBufferPointer { buffer in
            while offset < buffer.count {
                let count = write(fds[1], buffer.baseAddress! + offset, buffer.count - offset)
                if count <= 0 {
                    wroteEverything = false
                    break
                }
                offset += count
            }
        }
        close(fds[1])

        var status: Int32 = -1
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        return wroteEverything && status == 0
    }

    /// Writes the OSC 52 sequence to the terminal itself, bypassing stdout in
    /// case it is redirected.
    private static func sendOSC52(_ text: String) -> String? {
        let tty = open("/dev/tty", O_WRONLY)
        guard tty >= 0 else {
            return "no clipboard tool found and no terminal to send OSC 52 to"
        }
        defer { close(tty) }
        let bytes = Array(osc52(for: text).utf8)
        let written = bytes.withUnsafeBufferPointer { buffer in
            write(tty, buffer.baseAddress, buffer.count)
        }
        return written == bytes.count ? nil : "no clipboard tool found and the terminal refused OSC 52"
    }
}
