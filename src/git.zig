const std = @import("std");

pub const GitError = error{
    NotARepo,
    GitCommandFailed,
    InvalidStatusFormat,
    OutOfMemory,
};

pub const FileStatus = enum(u8) {
    unmodified = '.',
    modified = 'M',
    added = 'A',
    deleted = 'D',
    renamed = 'R',
    copied = 'C',
    type_changed = 'T',
    updated_unmerged = 'U',
    untracked = '?',
    ignored = '!',
    _,

    pub fn isUnmodified(self: FileStatus) bool {
        return self == .unmodified;
    }
};

pub const FileState = struct {
    staged: FileStatus,
    unstaged: FileStatus,
    original_path: ?[]const u8 = null,
    score: ?u8 = null,

    pub fn isUntracked(self: FileState) bool {
        return self.staged == .untracked and self.unstaged == .untracked;
    }

    pub fn hasStagedChanges(self: FileState) bool {
        return !self.staged.isUnmodified() and self.staged != .untracked;
    }

    pub fn hasUnstagedChanges(self: FileState) bool {
        return !self.unstaged.isUnmodified() and !self.isUntracked();
    }

    pub fn isRenamedOrCopied(self: FileState) bool {
        return self.staged == .renamed or self.staged == .copied or
            self.unstaged == .renamed or self.unstaged == .copied;
    }
};

pub const GitStatus = struct {
    arena: std.heap.ArenaAllocator,
    files: std.StringHashMap(FileState),

    pub fn init(allocator: std.mem.Allocator) GitStatus {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .files = std.StringHashMap(FileState).init(allocator),
        };
    }

    pub fn deinit(self: *GitStatus) void {
        self.files.deinit();
        self.arena.deinit();
    }

    pub fn ensureCapacity(self: *GitStatus, count: u32) !void {
        try self.files.ensureTotalCapacity(count);
    }

    pub fn hasChanges(self: GitStatus) bool {
        return self.files.count() > 0;
    }

    pub fn stagedCount(self: GitStatus) usize {
        var count: usize = 0;
        var iter = self.files.valueIterator();
        while (iter.next()) |state| {
            if (state.hasStagedChanges()) count += 1;
        }
        return count;
    }

    pub fn unstagedCount(self: GitStatus) usize {
        var count: usize = 0;
        var iter = self.files.valueIterator();
        while (iter.next()) |state| {
            if (state.hasUnstagedChanges()) count += 1;
        }
        return count;
    }

    pub fn untrackedCount(self: GitStatus) usize {
        var count: usize = 0;
        var iter = self.files.valueIterator();
        while (iter.next()) |state| {
            if (state.isUntracked()) count += 1;
        }
        return count;
    }

    pub fn stagedIterator(self: *GitStatus) StagedIterator {
        return .{
            .inner = self.files.iterator(),
        };
    }

    pub fn unstagedIterator(self: *GitStatus) UnstagedIterator {
        return .{
            .inner = self.files.iterator(),
        };
    }

    pub fn untrackedIterator(self: *GitStatus) UntrackedIterator {
        return .{
            .inner = self.files.iterator(),
        };
    }

    fn parseStatusChar(c: u8) FileStatus {
        // Porcelain v1 uses space, v2 uses dot for unmodified
        if (c == ' ' or c == '.') return .unmodified;
        return std.meta.intToEnum(FileStatus, c) catch .unmodified;
    }

    /// Get the field at the specified index from a space-separated line
    fn getField(line: []const u8, field_idx: usize) ?[]const u8 {
        var iter = std.mem.splitScalar(u8, line, ' ');
        var current_idx: usize = 0;

        while (iter.next()) |field| {
            if (current_idx == field_idx) {
                return field;
            }
            current_idx += 1;
        }

        return null;
    }

    pub fn parsePorcelainV2(self: *GitStatus, output: []const u8) !void {
        var lines = std.mem.splitScalar(u8, output, '\n');

        while (lines.next()) |line| {
            if (line.len == 0) continue;

            const line_type = line[0];

            switch (line_type) {
                '1' => {
                    // Ordinary file: 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
                    if (line.len < 4) continue;

                    const staged = parseStatusChar(line[2]);
                    const unstaged = parseStatusChar(line[3]);

                    // Path is field 8
                    if (getField(line, 8)) |path| {
                        const path_copy = try self.arena.allocator().dupe(u8, path);
                        try self.files.put(path_copy, .{
                            .staged = staged,
                            .unstaged = unstaged,
                        });
                    }
                },

                '2' => {
                    // Renamed/copied: 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path> [<origPath>]
                    if (line.len < 4) continue;

                    const staged = parseStatusChar(line[2]);
                    const unstaged = parseStatusChar(line[3]);

                    // Get path (field 9) and optional original path (field 10)
                    const path = getField(line, 9);
                    const orig_path = getField(line, 10);

                    // Parse score from field 8 (e.g., "R100" or "C95")
                    var score: ?u8 = null;
                    if (getField(line, 8)) |score_field| {
                        if (score_field.len >= 2 and (score_field[0] == 'R' or score_field[0] == 'C')) {
                            score = std.fmt.parseInt(u8, score_field[1..], 10) catch null;
                        }
                    }

                    if (path) |p| {
                        const path_copy = try self.arena.allocator().dupe(u8, p);
                        const orig_copy = if (orig_path) |op|
                            try self.arena.allocator().dupe(u8, op)
                        else
                            null;

                        try self.files.put(path_copy, .{
                            .staged = staged,
                            .unstaged = unstaged,
                            .original_path = orig_copy,
                            .score = score,
                        });
                    }
                },

                '?' => {
                    // Untracked: ? <path>
                    const path = std.mem.trimLeft(u8, line[1..], " ");
                    if (path.len > 0) {
                        const path_copy = try self.arena.allocator().dupe(u8, path);
                        try self.files.put(path_copy, .{
                            .staged = .untracked,
                            .unstaged = .untracked,
                        });
                    }
                },

                '!' => {
                    // Ignored: ! <path>
                    const path = std.mem.trimLeft(u8, line[1..], " ");
                    if (path.len > 0) {
                        const path_copy = try self.arena.allocator().dupe(u8, path);
                        try self.files.put(path_copy, .{
                            .staged = .ignored,
                            .unstaged = .ignored,
                        });
                    }
                },

                '#' => {
                    // Header line, skip
                    continue;
                },

                else => continue,
            }
        }
    }
};

pub const FileEntry = struct {
    path: []const u8,
    state: FileState,
};

/// Helper that filters iterator items by a predicate
fn nextFiltered(
    inner: *std.StringHashMap(FileState).Iterator,
    comptime predicate: fn (FileState) bool,
) ?FileEntry {
    while (inner.next()) |entry| {
        if (predicate(entry.value_ptr.*)) {
            return .{
                .path = entry.key_ptr.*,
                .state = entry.value_ptr.*,
            };
        }
    }
    return null;
}

pub const StagedIterator = struct {
    inner: std.StringHashMap(FileState).Iterator,

    pub fn next(self: *StagedIterator) ?FileEntry {
        return nextFiltered(&self.inner, FileState.hasStagedChanges);
    }
};

pub const UnstagedIterator = struct {
    inner: std.StringHashMap(FileState).Iterator,

    pub fn next(self: *UnstagedIterator) ?FileEntry {
        return nextFiltered(&self.inner, FileState.hasUnstagedChanges);
    }
};

pub const UntrackedIterator = struct {
    inner: std.StringHashMap(FileState).Iterator,

    pub fn next(self: *UntrackedIterator) ?FileEntry {
        return nextFiltered(&self.inner, FileState.isUntracked);
    }
};

pub fn isRepo() bool {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "git", "rev-parse", "--git-dir" },
        .max_output_bytes = 1024,
    }) catch return false;
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    return result.term.Exited == 0;
}

pub fn getStatus(allocator: std.mem.Allocator) !GitStatus {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "status", "--porcelain=v2", "--untracked-files=all" },
        .max_output_bytes = 10 * 1024 * 1024,
    }) catch return error.GitCommandFailed;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return error.GitCommandFailed;
    }

    var status = GitStatus.init(allocator);
    errdefer status.deinit();

    try status.ensureCapacity(10);
    try status.parsePorcelainV2(result.stdout);

    return status;
}

pub fn printGitStatus(writer: anytype, status: *GitStatus) !bool {
    if (!status.hasChanges()) {
        try writer.print("No changes to commit\n", .{});
        return false;
    }

    const green = "\x1b[32m";
    const red = "\x1b[31m";
    const yellow = "\x1b[33m";
    const reset = "\x1b[0m";

    var first_section = true;

    if (status.untrackedCount() > 0) {
        try writer.print("Untracked:\n", .{});
        var iter = status.untrackedIterator();
        while (iter.next()) |entry| {
            try writer.print("  {s}?{s} {s}\n", .{ red, reset, entry.path });
        }
        first_section = false;
    }

    if (status.unstagedCount() > 0) {
        if (!first_section) try writer.print("\n", .{});
        try writer.print("Unstaged:\n", .{});
        var iter = status.unstagedIterator();
        while (iter.next()) |entry| {
            const status_char: u8 = @intFromEnum(entry.state.unstaged);
            try writer.print("  {s}{c}{s} {s}\n", .{ yellow, status_char, reset, entry.path });
        }
        first_section = false;
    }

    if (status.stagedCount() > 0) {
        if (!first_section) try writer.print("\n", .{});
        try writer.print("Staged:\n", .{});
        var iter = status.stagedIterator();
        while (iter.next()) |entry| {
            const status_char: u8 = @intFromEnum(entry.state.staged);
            try writer.print("  {s}{c}{s} {s}\n", .{ green, status_char, reset, entry.path });
        }
    }

    return true;
}

pub fn addAll(allocator: std.mem.Allocator) !void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "add", "-A" },
        .max_output_bytes = 1024,
    }) catch return error.GitCommandFailed;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return error.GitCommandFailed;
    }
}

pub fn getStagedDiff(allocator: std.mem.Allocator) ![]const u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "diff", "--cached" },
        .max_output_bytes = 10 * 1024 * 1024, // 10MB max
    }) catch return error.GitCommandFailed;

    if (result.term.Exited != 0) {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
        return error.GitCommandFailed;
    }

    allocator.free(result.stderr);
    return result.stdout;
}

pub fn commit(allocator: std.mem.Allocator, message: []const u8) !void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "commit", "-m", message },
        .max_output_bytes = 10 * 1024,
    }) catch return error.GitCommandFailed;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return error.GitCommandFailed;
    }
}

pub fn push(allocator: std.mem.Allocator) !void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "push" },
        .max_output_bytes = 10 * 1024,
    }) catch return error.GitCommandFailed;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return error.GitCommandFailed;
    }
}

pub fn truncateDiff(allocator: std.mem.Allocator, diff: []const u8, max_size: usize) ![]const u8 {
    if (diff.len > max_size) {
        return std.fmt.allocPrint(allocator, "{s}\n... (truncated)", .{diff[0..max_size]});
    } else {
        return allocator.dupe(u8, diff);
    }
}

pub fn unstagedAndUntrackedCount(status: *GitStatus) usize {
    return status.unstagedCount() + status.untrackedCount();
}

test "isRepo detects git repository" {
    try std.testing.expect(isRepo());
}

test "FileStatus enum values" {
    try std.testing.expectEqual(@as(u8, 'M'), @intFromEnum(FileStatus.modified));
    try std.testing.expectEqual(@as(u8, 'A'), @intFromEnum(FileStatus.added));
    try std.testing.expectEqual(@as(u8, '?'), @intFromEnum(FileStatus.untracked));
}

test "FileState helpers" {
    const untracked_state = FileState{
        .staged = .untracked,
        .unstaged = .untracked,
    };
    try std.testing.expect(untracked_state.isUntracked());
    try std.testing.expect(!untracked_state.hasStagedChanges());
    try std.testing.expect(!untracked_state.hasUnstagedChanges());

    const staged_state = FileState{
        .staged = .added,
        .unstaged = .unmodified,
    };
    try std.testing.expect(!staged_state.isUntracked());
    try std.testing.expect(staged_state.hasStagedChanges());
    try std.testing.expect(!staged_state.hasUnstagedChanges());
}

// Unit tests with mock porcelain v2 data
test "parsePorcelainV2 getField helper" {
    const line = "1 .M N... 100644 100644 100644 abc def src/main.zig";
    try std.testing.expectEqualStrings("1", GitStatus.getField(line, 0).?);
    try std.testing.expectEqualStrings(".M", GitStatus.getField(line, 1).?);
    try std.testing.expectEqualStrings("src/main.zig", GitStatus.getField(line, 8).?);
    try std.testing.expect(GitStatus.getField(line, 100) == null);
}

test "parsePorcelainV2 ordinary file modified" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "1 .M N... 100644 100644 100644 abc def src/main.zig\n";
    try status.parsePorcelainV2(output);

    try std.testing.expectEqual(@as(usize, 1), status.files.count());

    const state = status.files.get("src/main.zig").?;
    try std.testing.expectEqual(FileStatus.unmodified, state.staged);
    try std.testing.expectEqual(FileStatus.modified, state.unstaged);
    try std.testing.expect(state.hasUnstagedChanges());
    try std.testing.expect(!state.hasStagedChanges());
}

test "parsePorcelainV2 ordinary file added" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "1 A. N... 000000 100644 100644 abc def new_file.txt\n";
    try status.parsePorcelainV2(output);

    const state = status.files.get("new_file.txt").?;
    try std.testing.expectEqual(FileStatus.added, state.staged);
    try std.testing.expectEqual(FileStatus.unmodified, state.unstaged);
    try std.testing.expect(state.hasStagedChanges());
    try std.testing.expect(!state.hasUnstagedChanges());
}

test "parsePorcelainV2 ordinary file deleted" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "1 D. N... 100644 000000 000000 abc def deleted.txt\n";
    try status.parsePorcelainV2(output);

    const state = status.files.get("deleted.txt").?;
    try std.testing.expectEqual(FileStatus.deleted, state.staged);
    try std.testing.expectEqual(FileStatus.unmodified, state.unstaged);
}

test "parsePorcelainV2 modified both staged and unstaged" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "1 MM N... 100644 100644 100644 abc def modified.txt\n";
    try status.parsePorcelainV2(output);

    const state = status.files.get("modified.txt").?;
    try std.testing.expectEqual(FileStatus.modified, state.staged);
    try std.testing.expectEqual(FileStatus.modified, state.unstaged);
    try std.testing.expect(state.hasStagedChanges());
    try std.testing.expect(state.hasUnstagedChanges());
}

test "parsePorcelainV2 added then modified" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "1 AM N... 000000 100644 100644 abc def added_then_modified.txt\n";
    try status.parsePorcelainV2(output);

    const state = status.files.get("added_then_modified.txt").?;
    try std.testing.expectEqual(FileStatus.added, state.staged);
    try std.testing.expectEqual(FileStatus.modified, state.unstaged);
}

test "parsePorcelainV2 untracked files" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "? untracked1.txt\n? untracked2.txt\n";
    try status.parsePorcelainV2(output);

    try std.testing.expectEqual(@as(usize, 2), status.files.count());

    const state1 = status.files.get("untracked1.txt").?;
    try std.testing.expect(state1.isUntracked());
    try std.testing.expectEqual(FileStatus.untracked, state1.staged);
    try std.testing.expectEqual(FileStatus.untracked, state1.unstaged);
}

test "parsePorcelainV2 ignored files" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "! ignored.log\n";
    try status.parsePorcelainV2(output);

    const state = status.files.get("ignored.log").?;
    try std.testing.expectEqual(FileStatus.ignored, state.staged);
    try std.testing.expectEqual(FileStatus.ignored, state.unstaged);
}

test "parsePorcelainV2 renamed file with score" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "2 R. N... 100644 100644 100644 abc def R95 new_name.txt old_name.txt\n";
    try status.parsePorcelainV2(output);

    const state = status.files.get("new_name.txt").?;
    try std.testing.expectEqual(FileStatus.renamed, state.staged);
    try std.testing.expectEqual(FileStatus.unmodified, state.unstaged);
    try std.testing.expect(state.original_path != null);
    try std.testing.expectEqualStrings("old_name.txt", state.original_path.?);
    try std.testing.expectEqual(@as(u8, 95), state.score.?);
    try std.testing.expect(state.isRenamedOrCopied());
}

test "parsePorcelainV2 copied file" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "2 C. N... 100644 100644 100644 abc def C80 copied.txt original.txt\n";
    try status.parsePorcelainV2(output);

    const state = status.files.get("copied.txt").?;
    try std.testing.expectEqual(FileStatus.copied, state.staged);
    try std.testing.expectEqualStrings("original.txt", state.original_path.?);
    try std.testing.expectEqual(@as(u8, 80), state.score.?);
}

test "parsePorcelainV2 multiple files" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output =
        "# branch-oid abc123\n" ++
        "1 .M N... 100644 100644 100644 abc def src/main.zig\n" ++
        "1 A. N... 000000 100644 100644 abc def new.txt\n" ++
        "? untracked.txt\n" ++
        "2 R. N... 100644 100644 100644 abc def R100 renamed.txt old.txt\n";

    try status.parsePorcelainV2(output);

    try std.testing.expectEqual(@as(usize, 4), status.files.count());
    try std.testing.expectEqual(@as(usize, 2), status.stagedCount()); // added + renamed
    try std.testing.expectEqual(@as(usize, 1), status.unstagedCount()); // modified
    try std.testing.expectEqual(@as(usize, 1), status.untrackedCount()); // untracked
}

test "parsePorcelainV2 empty output" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    try status.parsePorcelainV2("");
    try std.testing.expectEqual(@as(usize, 0), status.files.count());
    try std.testing.expect(!status.hasChanges());
}

test "parsePorcelainV2 header lines only" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "# branch-oid abc123\n# branch-head main\n";
    try status.parsePorcelainV2(output);
    try std.testing.expectEqual(@as(usize, 0), status.files.count());
}

test "parsePorcelainV2 file with spaces in name" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "? file with spaces.txt\n";
    try status.parsePorcelainV2(output);

    const state = status.files.get("file with spaces.txt").?;
    try std.testing.expect(state.isUntracked());
}

test "parsePorcelainV2 type changed" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "1 T. N... 100644 120000 120000 abc def symlink\n";
    try status.parsePorcelainV2(output);

    const state = status.files.get("symlink").?;
    try std.testing.expectEqual(FileStatus.type_changed, state.staged);
}

test "parsePorcelainV2 deleted unstaged" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output = "1 .D N... 100644 100644 000000 abc def removed.txt\n";
    try status.parsePorcelainV2(output);

    const state = status.files.get("removed.txt").?;
    try std.testing.expectEqual(FileStatus.unmodified, state.staged);
    try std.testing.expectEqual(FileStatus.deleted, state.unstaged);
    try std.testing.expect(!state.hasStagedChanges());
    try std.testing.expect(state.hasUnstagedChanges());
}

test "GitStatus counters and iterators" {
    var status = GitStatus.init(std.testing.allocator);
    defer status.deinit();

    const output =
        "1 A. N... 000000 100644 100644 abc def staged.txt\n" ++
        "1 .M N... 100644 100644 100644 abc def unstaged.txt\n" ++
        "1 AM N... 000000 100644 100644 abc def both.txt\n" ++
        "? untracked.txt\n";

    try status.parsePorcelainV2(output);

    // staged: staged.txt, both.txt (AM) = 2
    try std.testing.expectEqual(@as(usize, 2), status.stagedCount());

    // unstaged: unstaged.txt, both.txt (AM) = 2
    try std.testing.expectEqual(@as(usize, 2), status.unstagedCount());

    // untracked: untracked.txt = 1
    try std.testing.expectEqual(@as(usize, 1), status.untrackedCount());

    // Test staged iterator
    var staged_iter = status.stagedIterator();
    var staged_count: usize = 0;
    while (staged_iter.next()) |_| staged_count += 1;
    try std.testing.expectEqual(@as(usize, 2), staged_count);

    // Test unstaged iterator
    var unstaged_iter = status.unstagedIterator();
    var unstaged_count: usize = 0;
    while (unstaged_iter.next()) |_| unstaged_count += 1;
    try std.testing.expectEqual(@as(usize, 2), unstaged_count);

    // Test untracked iterator
    var untracked_iter = status.untrackedIterator();
    var untracked_count: usize = 0;
    while (untracked_iter.next()) |_| untracked_count += 1;
    try std.testing.expectEqual(@as(usize, 1), untracked_count);
}
