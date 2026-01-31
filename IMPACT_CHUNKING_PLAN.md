# Impact-Aware Diff Chunking Implementation Plan

## Overview

Replace simple diff truncation with intelligent token-based chunking that preserves file boundaries and extracts structured impact information from each chunk. This approach ensures no critical changes are lost when dealing with large diffs that exceed LLM token limits.

## User Requirements Summary

Based on clarifying questions:
- **Lockfiles**: Completely skipped (not sent to LLM)
- **Breaking changes**: Detected by LLM based on context
- **Large files (>5k tokens)**: Skipped entirely with warning
- **Processing**: Parallel chunk processing
- **Output format**: Structured text (not JSON/XML)
- **Token estimation**: Simple bytes/4 approach
- **Caching**: No caching (reprocess every time)
- **Failure handling**: Fail entire commit generation if extraction fails
- **Configuration**: Configurable via config file (not CLI flags)

## Architecture

### New Module: `src/diff_processor.zig`

Responsible for parsing diffs, chunking by tokens while preserving file boundaries, parallel processing of chunks for impact extraction, and combining results into final commit message.

### Data Structures

```zig
pub const FileDiff = struct {
    path: []const u8,
    content: []const u8,
    change_type: ChangeType,
    estimated_tokens: usize,
};

pub const ChangeType = enum {
    added,
    modified,
    deleted,
    renamed,
    copied,
};

pub const FileExtraction = struct {
    path: []const u8,
    change_type: ChangeType,
    summary: []const u8,
    key_changes: []const []const u8,
    impact_level: ImpactLevel,
    breaking_change: bool,
    rationale: []const u8,
};

pub const ImpactLevel = enum {
    low,
    medium,
    high,
    critical,
};

pub const Chunk = struct {
    files: []const FileDiff,
    estimated_tokens: usize,
};

pub const SkippedFile = struct {
    path: []const u8,
    reason: enum { too_large, lockfile, binary },
};

pub const ProcessingResult = struct {
    chunks: []const Chunk,
    skipped_files: []const SkippedFile,
    extractions: []const []const FileExtraction,
};

pub const DiffProcessor = struct {
    allocator: std.mem.Allocator,
    provider: *llm.Provider,
    config: Config,
    
    const Config = struct {
        max_tokens_per_chunk: usize,
        max_file_tokens: usize,
        skip_lockfiles: bool,
        skip_binaries: bool,
    };
    
    pub fn init(allocator: std.mem.Allocator, provider: *llm.Provider, config: Config) DiffProcessor;
    pub fn process(self: *DiffProcessor, diff: []const u8) !ProcessingResult;
    pub fn generateCommitMessage(self: *DiffProcessor, result: ProcessingResult, system_prompt: []const u8) ![]const u8;
    pub fn deinit(self: *DiffProcessor);
};
```

## Implementation Phases

### Phase 1: Core Diff Parsing (2-3 hours)

#### 1.1 Parse Diff into File Segments

**Algorithm:**
1. Split diff on `diff --git a/` pattern
2. For each segment:
   - Extract old and new paths from header
   - Determine change type from header format:
     - `diff --git a/X b/X` + `--- a/X` + `+++ b/X` = modified
     - `diff --git a/X b/X` + `--- /dev/null` = added
     - `diff --git a/X b/X` + `+++ /dev/null` = deleted
     - `diff --git a/X b/Y` = renamed or copied (check for similarity score)
   - Estimate tokens: `content.len / 4`
   - Store in FileDiff struct

**Edge Cases:**
- Handle file paths with spaces (quoted in git diff)
- Handle renamed files with similarity scores
- Handle binary files (marked with "Binary files differ")

#### 1.2 Lockfile Detection

```zig
const LOCKFILE_NAMES = &.{
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "npm-shrinkwrap.json",
    "Cargo.lock",
    "Gemfile.lock",
    "composer.lock",
    "poetry.lock",
    "Pipfile.lock",
    "go.sum",
    "flake.lock",
    "mix.lock",
    "pnpm-lock.yml",
};

fn isLockfile(path: []const u8) bool {
    const basename = std.fs.path.basename(path);
    for (LOCKFILE_NAMES) |name| {
        if (std.mem.eql(u8, basename, name)) return true;
    }
    return false;
}
```

#### 1.3 Binary File Detection

```zig
fn isBinaryFile(path: []const u8, content: []const u8) bool {
    // Check by extension
    const binary_extensions = &.{
        ".exe", ".dll", ".so", ".dylib",
        ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".svg",
        ".ico", ".pdf", ".zip", ".tar", ".gz", ".bz2",
        ".7z", ".rar", ".mp3", ".mp4", ".avi", ".mov",
        ".woff", ".woff2", ".ttf", ".otf", ".eot",
    };
    
    const ext = std.fs.path.extension(path);
    for (binary_extensions) |bin_ext| {
        if (std.mem.eql(u8, ext, bin_ext)) return true;
    }
    
    // Check by diff content marker
    if (std.mem.indexOf(u8, content, "Binary files") != null) return true;
    
    return false;
}
```

### Phase 2: Token-Based Chunking (2-3 hours)

#### 2.1 Chunking Algorithm

**Greedy Bin Packing Strategy:**
```zig
fn chunkFiles(allocator: Allocator, files: []const FileDiff, max_tokens: usize) ![]Chunk {
    var chunks = std.ArrayList(Chunk).init(allocator);
    var current_chunk_files = std.ArrayList(FileDiff).init(allocator);
    var current_tokens: usize = 0;
    
    // Sort files by token count (largest first) for better packing
    var sorted_files = try allocator.dupe(FileDiff, files);
    defer allocator.free(sorted_files);
    std.sort.block(FileDiff, sorted_files, {}, compareByTokenCountDesc);
    
    for (sorted_files) |file| {
        // Safety margin: leave 10% buffer for token estimation inaccuracy
        const safe_max = max_tokens * 9 / 10;
        
        if (current_tokens + file.estimated_tokens <= safe_max) {
            // Add to current chunk
            try current_chunk_files.append(file);
            current_tokens += file.estimated_tokens;
        } else {
            // Finish current chunk and start new one
            if (current_chunk_files.items.len > 0) {
                try chunks.append(Chunk{
                    .files = try current_chunk_files.toOwnedSlice(),
                    .estimated_tokens = current_tokens,
                });
            }
            
            // Start new chunk with current file
            current_chunk_files = std.ArrayList(FileDiff).init(allocator);
            try current_chunk_files.append(file);
            current_tokens = file.estimated_tokens;
        }
    }
    
    // Don't forget the last chunk
    if (current_chunk_files.items.len > 0) {
        try chunks.append(Chunk{
            .files = try current_chunk_files.toOwnedSlice(),
            .estimated_tokens = current_tokens,
        });
    }
    
    return chunks.toOwnedSlice();
}
```

**Token Estimation:**
- Simple conservative estimate: `tokens = content.len / 4`
- Add overhead for JSON encoding, prompt template, system message
- Target 3500 tokens per chunk (leaves ~1500 for prompt overhead + response)

#### 2.2 Filtering Files

```zig
fn filterFiles(
    allocator: Allocator,
    files: []const FileDiff,
    config: Config,
    skipped: *std.ArrayList(SkippedFile),
) ![]FileDiff {
    var filtered = std.ArrayList(FileDiff).init(allocator);
    
    for (files) |file| {
        if (config.skip_lockfiles and isLockfile(file.path)) {
            try skipped.append(.{
                .path = file.path,
                .reason = .lockfile,
            });
            continue;
        }
        
        if (config.skip_binaries and isBinaryFile(file.path, file.content)) {
            try skipped.append(.{
                .path = file.path,
                .reason = .binary,
            });
            continue;
        }
        
        if (file.estimated_tokens > config.max_file_tokens) {
            try skipped.append(.{
                .path = file.path,
                .reason = .too_large,
            });
            continue;
        }
        
        try filtered.append(file);
    }
    
    return filtered.toOwnedSlice();
}
```

### Phase 3: Impact Extraction Prompts (2-3 hours)

#### 3.1 Extraction Prompt Template

```zig
const EXTRACTION_PROMPT =
    \You are analyzing code changes to extract structured impact information.
    \
    \Analyze the following git diff and extract key information for each file:
    \
    \{diff_content}
    \
    \For each file changed, provide:
    \1. SUMMARY: 1-2 factual sentences describing WHAT changed
    \2. KEY_CHANGES: Bullet list of specific modifications (functions, APIs, etc.)
    \3. IMPACT: One of LOW/MEDIUM/HIGH/CRITICAL based on significance
    \4. BREAKING: YES or NO - does this change public APIs or behavior?
    \5. RATIONALE: Briefly infer WHY this change was made
    \
    \Format exactly as:
    \
    \FILE: src/example.zig
    \SUMMARY: Added input validation to prevent empty string submissions
    \KEY_CHANGES:
    \- Added validateInput() function
    \- Modified processForm() to call validator
    \IMPACT: HIGH
    \BREAKING: NO
    \RATIONALE: Prevents crash when users submit empty forms
    \
    \FILE: src/api.zig
    \SUMMARY: Changed authentication endpoint path
    \KEY_CHANGES:
    \- Updated endpoint URL from /login to /auth/v2/login
    \- Added client_id parameter requirement
    \IMPACT: CRITICAL
    \BREAKING: YES
    \RATIONALE: API v2 migration requiring client identification
    \
    \Be precise and factual. Don't omit important details.
;
```

#### 3.2 Building Chunk Content

```zig
fn buildChunkContent(allocator: Allocator, chunk: Chunk) ![]const u8 {
    var content = std.ArrayList(u8).init(allocator);
    var writer = content.writer();
    
    for (chunk.files) |file| {
        try writer.print("\nFILE: {s}\n", .{file.path});
        try writer.print("CHANGE_TYPE: {s}\n", .{@tagName(file.change_type)});
        try writer.writeAll(file.content);
        try writer.writeAll("\n");
    }
    
    return content.toOwnedSlice();
}
```

### Phase 4: Response Parsing (3-4 hours)

#### 4.1 Parse Extraction Response

```zig
fn parseExtractionResponse(
    allocator: Allocator,
    response: []const u8,
    expected_files: []const FileDiff,
) ![]FileExtraction {
    var extractions = std.ArrayList(FileExtraction).init(allocator);
    
    // Parse response line by line
    var lines = std.mem.splitScalar(u8, response, '\n');
    var current_extraction: ?FileExtraction = null;
    var in_key_changes = false;
    var key_changes_list = std.ArrayList([]const u8).init(allocator);
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        
        if (std.mem.startsWith(u8, trimmed, "FILE: ")) {
            // Save previous extraction if exists
            if (current_extraction) |*ext| {
                ext.key_changes = try key_changes_list.toOwnedSlice();
                try extractions.append(ext.*);
                key_changes_list = std.ArrayList([]const u8).init(allocator);
            }
            
            // Start new extraction
            const path = trimmed[6..]; // Skip "FILE: "
            current_extraction = FileExtraction{
                .path = try allocator.dupe(u8, path),
                .change_type = .modified, // Will be updated
                .summary = &.{},
                .key_changes = &.{},
                .impact_level = .medium,
                .breaking_change = false,
                .rationale = &.{},
            };
            in_key_changes = false;
            
        } else if (current_extraction) |*ext| {
            if (std.mem.startsWith(u8, trimmed, "SUMMARY: ")) {
                ext.summary = try allocator.dupe(u8, trimmed[9..]);
                in_key_changes = false;
                
            } else if (std.mem.startsWith(u8, trimmed, "KEY_CHANGES:")) {
                in_key_changes = true;
                
            } else if (in_key_changes and std.mem.startsWith(u8, trimmed, "- ")) {
                const change = trimmed[2..];
                try key_changes_list.append(try allocator.dupe(u8, change));
                
            } else if (std.mem.startsWith(u8, trimmed, "IMPACT: ")) {
                const impact_str = trimmed[8..];
                ext.impact_level = parseImpactLevel(impact_str);
                in_key_changes = false;
                
            } else if (std.mem.startsWith(u8, trimmed, "BREAKING: ")) {
                const breaking_str = trimmed[10..];
                ext.breaking_change = std.mem.eql(u8, breaking_str, "YES");
                in_key_changes = false;
                
            } else if (std.mem.startsWith(u8, trimmed, "RATIONALE: ")) {
                ext.rationale = try allocator.dupe(u8, trimmed[11..]);
                in_key_changes = false;
            }
        }
    }
    
    // Save last extraction
    if (current_extraction) |*ext| {
        ext.key_changes = try key_changes_list.toOwnedSlice();
        try extractions.append(ext.*);
    }
    
    // Map change types from expected files
    for (extractions.items) |*ext| {
        for (expected_files) |file| {
            if (std.mem.eql(u8, ext.path, file.path)) {
                ext.change_type = file.change_type;
                break;
            }
        }
    }
    
    return extractions.toOwnedSlice();
}

fn parseImpactLevel(str: []const u8) ImpactLevel {
    if (std.mem.eql(u8, str, "LOW")) return .low;
    if (std.mem.eql(u8, str, "MEDIUM")) return .medium;
    if (std.mem.eql(u8, str, "HIGH")) return .high;
    if (std.mem.eql(u8, str, "CRITICAL")) return .critical;
    return .medium; // Default
}
```

### Phase 5: Parallel Processing (3-4 hours)

#### 5.1 Async Chunk Processing

Zig doesn't have built-in async/await yet, so we'll use a thread pool pattern:

```zig
const ChunkJob = struct {
    chunk: Chunk,
    extraction: ?[]FileExtraction,
    error_message: ?[]const u8,
};

fn processChunksParallel(
    self: *DiffProcessor,
    chunks: []const Chunk,
) ![][]FileExtraction {
    const max_concurrent = 3; // Limit concurrent requests to respect rate limits
    
    var jobs = try self.allocator.alloc(ChunkJob, chunks.len);
    defer self.allocator.free(jobs);
    
    // Initialize jobs
    for (chunks, 0..) |chunk, i| {
        jobs[i] = .{
            .chunk = chunk,
            .extraction = null,
            .error_message = null,
        };
    }
    
    // Process in batches
    var processed: usize = 0;
    while (processed < chunks.len) {
        const batch_size = @min(max_concurrent, chunks.len - processed);
        
        // Spawn threads for this batch
        var threads = try self.allocator.alloc(std.Thread, batch_size);
        defer self.allocator.free(threads);
        
        for (0..batch_size) |i| {
            const job_index = processed + i;
            threads[i] = try std.Thread.spawn(.{}, processChunkWorker, .{
                self,
                &jobs[job_index],
            });
        }
        
        // Wait for all threads in batch
        for (threads) |thread| {
            thread.join();
        }
        
        processed += batch_size;
    }
    
    // Collect results
    var all_extractions = std.ArrayList([]FileExtraction).init(self.allocator);
    for (jobs) |job| {
        if (job.error_message) |err| {
            std.log.err("Chunk processing failed: {s}", .{err});
            return error.ChunkProcessingFailed;
        }
        if (job.extraction) |ext| {
            try all_extractions.append(ext);
        }
    }
    
    return all_extractions.toOwnedSlice();
}

fn processChunkWorker(self: *DiffProcessor, job: *ChunkJob) void {
    const extraction = self.extractChunkImpact(job.chunk) catch |err| {
        job.error_message = std.fmt.allocPrint(
            self.allocator,
            "{s}",
            .{@errorName(err)},
        ) catch "Unknown error";
        return;
    };
    job.extraction = extraction;
}

fn extractChunkImpact(self: *DiffProcessor, chunk: Chunk) ![]FileExtraction {
    const chunk_content = try buildChunkContent(self.allocator, chunk);
    defer self.allocator.free(chunk_content);
    
    const prompt = try std.fmt.allocPrint(
        self.allocator,
        EXTRACTION_PROMPT,
        .{ .diff_content = chunk_content },
    );
    defer self.allocator.free(prompt);
    
    const response = try self.provider.generateCommitMessage(chunk_content, prompt);
    // Note: provider.generateCommitMessage expects a diff, but we're using it
    // with our extraction prompt. We may need to add a new method or modify.
    
    return try parseExtractionResponse(self.allocator, response, chunk.files);
}
```

**Note:** The current `provider.generateCommitMessage` is designed for the final commit message generation. We'll need to add a new method like `provider.extractImpact(diff: []const u8, prompt: []const u8)` that uses the same HTTP infrastructure but with different prompts.

### Phase 6: Combining Extractions (2-3 hours)

#### 6.1 Sort and Format

```zig
fn combineExtractions(
    self: *DiffProcessor,
    extractions: []const []const FileExtraction,
    skipped_files: []const SkippedFile,
) ![]const u8 {
    // Flatten all extractions into single array
    var flat = std.ArrayList(FileExtraction).init(self.allocator);
    for (extractions) |chunk_exts| {
        for (chunk_exts) |ext| {
            try flat.append(ext);
        }
    }
    
    // Sort by impact level (critical first)
    std.sort.block(FileExtraction, flat.items, {}, compareByImpactDesc);
    
    // Build formatted document
    var output = std.ArrayList(u8).init(self.allocator);
    var writer = output.writer();
    
    // Section: Critical Changes (Breaking)
    var has_critical = false;
    for (flat.items) |ext| {
        if (ext.impact_level == .critical or ext.breaking_change) {
            if (!has_critical) {
                try writer.writeAll("\nCRITICAL CHANGES (Breaking):\n");
                has_critical = true;
            }
            try formatExtraction(writer, ext);
        }
    }
    
    // Section: High Impact
    var has_high = false;
    for (flat.items) |ext| {
        if (ext.impact_level == .high and !ext.breaking_change) {
            if (!has_high) {
                try writer.writeAll("\nHIGH IMPACT:\n");
                has_high = true;
            }
            try formatExtraction(writer, ext);
        }
    }
    
    // Section: Medium Impact
    var has_medium = false;
    for (flat.items) |ext| {
        if (ext.impact_level == .medium) {
            if (!has_medium) {
                try writer.writeAll("\nMEDIUM IMPACT:\n");
                has_medium = true;
            }
            try formatExtraction(writer, ext);
        }
    }
    
    // Section: Low Impact (brief)
    var has_low = false;
    for (flat.items) |ext| {
        if (ext.impact_level == .low) {
            if (!has_low) {
                try writer.writeAll("\nLOW IMPACT:\n");
                has_low = true;
            }
            try writer.print("- {s}: {s}\n", .{ ext.path, ext.summary });
        }
    }
    
    // Section: Skipped Files
    if (skipped_files.len > 0) {
        try writer.writeAll("\nSKIPPED FILES:\n");
        for (skipped_files) |skipped| {
            const reason_str = switch (skipped.reason) {
                .too_large => "too large (>5000 tokens)",
                .lockfile => "lockfile",
                .binary => "binary file",
            };
            try writer.print("- {s} ({s})\n", .{ skipped.path, reason_str });
        }
    }
    
    return output.toOwnedSlice();
}

fn formatExtraction(writer: anytype, ext: FileExtraction) !void {
    try writer.print("\n{s}:\n", .{ext.path});
    try writer.print("  Summary: {s}\n", .{ext.summary});
    if (ext.key_changes.len > 0) {
        try writer.writeAll("  Key Changes:\n");
        for (ext.key_changes) |change| {
            try writer.print("    - {s}\n", .{change});
        }
    }
    try writer.print("  Impact: {s}\n", .{@tagName(ext.impact_level)});
    if (ext.breaking_change) {
        try writer.writeAll("  BREAKING: YES\n");
    }
    try writer.print("  Rationale: {s}\n", .{ext.rationale});
}

fn compareByImpactDesc(_: void, a: FileExtraction, b: FileExtraction) bool {
    const impact_order = [_]u8{ 3, 2, 1, 0 }; // critical=3, high=2, medium=1, low=0
    const a_val = impact_order[@intFromEnum(a.impact_level)];
    const b_val = impact_order[@intFromEnum(b.impact_level)];
    return a_val > b_val;
}
```

### Phase 7: Final Commit Generation (2 hours)

#### 7.1 Final Prompt

```zig
const FINAL_COMMIT_PROMPT =
    \You are a commit message generator. Based on the structured analysis below, write a conventional commit message.
    \
    \{combined_analysis}
    \
    \Rules:
    \- Use format: <type>(<scope>): <subject>
    \- Types: feat, fix, docs, style, refactor, test, chore, perf, security
    \- Scope: Primary module affected (optional for single-file changes)
    \- Subject: Max 50 chars, imperative mood, no period
    \- Body: Use bullet points for multiple significant changes
    \- Breaking Changes: Add "BREAKING CHANGE:" section if any marked breaking
    \- Prioritize: Mention critical/high impact changes first in subject
    \
    \Write ONLY the commit message, no explanation.
;
```

#### 7.2 Generate Final Message

```zig
fn generateCommitMessage(
    self: *DiffProcessor,
    result: ProcessingResult,
    system_prompt: []const u8,
) ![]const u8 {
    // If only one chunk and no skipped files, we could skip the two-stage process
    // But for consistency, we'll always do extraction + final generation
    
    const combined = try combineExtractions(self, result.extractions, result.skipped_files);
    defer self.allocator.free(combined);
    
    const final_prompt = try std.fmt.allocPrint(
        self.allocator,
        FINAL_COMMIT_PROMPT,
        .{ .combined_analysis = combined },
    );
    defer self.allocator.free(final_prompt);
    
    // Create a minimal diff (or use empty string) since we're providing full context in prompt
    // The provider will still call the LLM with our structured prompt
    const dummy_diff = "See analysis above";
    
    return try self.provider.generateCommitMessage(dummy_diff, final_prompt);
}
```

### Phase 8: Integration (2-3 hours)

#### 8.1 Update `main.zig`

Replace lines 186-212:

```zig
// OLD CODE:
// const diff = try git.getStagedDiff(allocator);
// defer allocator.free(diff);
// const max_diff_size = 100 * 1024;
// const truncated_diff = try git.truncateDiff(allocator, diff, max_diff_size);
// defer allocator.free(truncated_diff);
// const commit_message = provider.generateCommitMessage(truncated_diff, cfg.system_prompt) catch |err| {
//     ...
// };

// NEW CODE:
const diff = try git.getStagedDiff(allocator);
defer allocator.free(diff);

// Check if we need chunking (simple heuristic)
const SIMPLE_DIFF_THRESHOLD = 15 * 1024; // ~15KB, roughly 3750 tokens
const diff_processor = @import("diff_processor.zig");

var processor = diff_processor.DiffProcessor.init(
    allocator,
    &provider,
    .{
        .max_tokens_per_chunk = cfg.chunking.max_tokens_per_chunk,
        .max_file_tokens = cfg.chunking.max_file_tokens,
        .skip_lockfiles = cfg.chunking.skip_lockfiles,
        .skip_binaries = cfg.chunking.skip_binaries,
    },
);
defer processor.deinit();

const processing_result = try processor.process(diff);

// Check if any files were processed
if (processing_result.chunks.len == 0) {
    if (processing_result.skipped_files.len > 0) {
        try stderr.print("Error: All files were skipped (too large or lockfiles).\n", .{});
        try stderr.print("Consider using manual commit or adjusting config.\n", .{});
    } else {
        try stderr.print("Error: No changes to process.\n", .{});
    }
    std.process.exit(1);
}

// Generate commit message from processed chunks
const commit_message = processor.generateCommitMessage(
    processing_result,
    cfg.system_prompt,
) catch |err| {
    const error_message = switch (err) {
        error.ChunkProcessingFailed => "Failed to analyze changes. Please try again or use a smaller diff.",
        error.RateLimited => "Rate limit exceeded. Please try again later.",
        error.ServerError => "Server error from LLM provider.",
        error.Timeout => "Request timed out.",
        error.InvalidResponse => "Invalid response from LLM.",
        error.EmptyContent => "LLM returned empty analysis.",
        error.ApiError => "API error occurred.",
        error.OutOfMemory => "Out of memory.",
        else => "Unexpected error during processing.",
    };
    try stderr.print("Error: {s}\n", .{error_message});
    std.process.exit(1);
};
```

#### 8.2 Add Chunking Config to `config.zig`

Update the `Config` struct (around line 90):

```zig
pub const Config = struct {
    default_provider: []const u8,
    system_prompt: []const u8,
    providers: []ProviderConfig,
    chunking: ChunkingConfig,
    
    pub fn deinit(self: *const Config, allocator: std.mem.Allocator) void {
        allocator.free(self.default_provider);
        allocator.free(self.system_prompt);
        for (self.providers) |provider| {
            provider.deinit(allocator);
        }
        allocator.free(self.providers);
        // ChunkingConfig has no allocated memory
    }
    ...
};

pub const ChunkingConfig = struct {
    max_tokens_per_chunk: usize = 3500,
    max_file_tokens: usize = 5000,
    skip_lockfiles: bool = true,
    skip_binaries: bool = true,
};
```

Update the default config template (around line 75):

```zig
return std.fmt.comptimePrint(
    "default_provider = \"{s}\"\n\n" ++
        "system_prompt = \"\"\"\n{s}\"\"\"\n\n" ++
        "[chunking]\n" ++
        "max_tokens_per_chunk = 3500\n" ++
        "max_file_tokens = 5000\n" ++
        "skip_lockfiles = true\n" ++
        "skip_binaries = true\n\n" ++
        "{s}",
    .{
        default_provider.name(),
        SYSTEM_PROMPT_TEMPLATE,
        providers_section,
    },
);
```

The tomlz parser will automatically handle the [chunking] table and populate the struct.

### Phase 9: Update Provider Interface (1-2 hours)

#### 9.1 Add Generic Request Method

In `src/llm.zig`, add a method for generic LLM requests:

```zig
pub fn sendRequest(
    self: Provider,
    system_prompt: []const u8,
    user_content: []const u8,
) LlmError![]const u8 {
    // Similar to generateCommitMessage but with custom prompts
    self.logDebug("Building custom LLM request...", .{});
    
    const request_body = try self.buildCustomRequest(system_prompt, user_content);
    defer self.allocator.free(request_body);
    
    self.logDebug("Request body size: {d} bytes", .{request_body.len});
    
    const endpoint = self.vtable.getEndpoint(self);
    const auth_header = try self.vtable.getAuthHeader(self);
    defer self.allocator.free(auth_header);
    
    self.logDebug("Sending request to {s}", .{endpoint});
    
    const response_body = self.http.postJson(endpoint, auth_header, request_body) catch |err| {
        std.log.err("HTTP request failed: {s}", .{@errorName(err)});
        return mapHttpError(err);
    });
    defer self.allocator.free(response_body);
    
    self.logDebug("Raw LLM response: {s}", .{response_body});
    
    return self.vtable.parseResponse(self, response_body);
}

fn buildCustomRequest(
    self: Provider,
    system_prompt: []const u8,
    user_content: []const u8,
) ![]const u8 {
    const allocator = self.allocator;
    
    const messages = &[_]Message{
        .{ .role = "system", .content = system_prompt },
        .{ .role = "user", .content = user_content },
    };
    
    const request = .{
        .model = self.config.model,
        .messages = messages,
        .temperature = @as(f32, 0.3), // Lower temp for structured extraction
        .max_tokens = @as(u32, 2000), // Extraction responses are longer
    };
    
    return std.json.stringifyAlloc(allocator, request, .{
        .emit_null_optional_fields = false,
    });
}
```

This allows `diff_processor.zig` to use the same LLM infrastructure with different prompts.

### Phase 10: Testing (4-5 hours)

#### 10.1 Unit Tests

Create `src/diff_processor_tests.zig`:

```zig
const std = @import("std");
const diff_processor = @import("diff_processor.zig");

test "parse diff into files - single file" {
    const diff =
        \\diff --git a/src/main.zig b/src/main.zig
        \\index abc..def 100644
        \\--- a/src/main.zig
        \\+++ b/src/main.zig
        \\@@ -10,5 +10,7 @@ pub fn main() void {
        \\     const x = 5;
        \\+    const y = 10;
        \\     std.debug.print("{d}", .{x});
        \\ }
    ;
    
    var files = try diff_processor.parseDiff(std.testing.allocator, diff);
    defer diff_processor.freeFiles(std.testing.allocator, files);
    
    try std.testing.expectEqual(@as(usize, 1), files.len);
    try std.testing.expectEqualStrings("src/main.zig", files[0].path);
    try std.testing.expectEqual(.modified, files[0].change_type);
}

test "parse diff - added file" {
    const diff =
        \\diff --git a/src/new.zig b/src/new.zig
        \\new file mode 100644
        \\index 0000000..abc1234
        \\--- /dev/null
        \\+++ b/src/new.zig
        \\@@ -0,0 +1,10 @@
        \\+pub fn newFunction() void {
        \\+    return 42;
        \\+}
    ;
    
    var files = try diff_processor.parseDiff(std.testing.allocator, diff);
    defer diff_processor.freeFiles(std.testing.allocator, files);
    
    try std.testing.expectEqual(@as(usize, 1), files.len);
    try std.testing.expectEqual(.added, files[0].change_type);
}

test "chunk files respects token limit" {
    // Create test files with known token counts
    const files = &[_]diff_processor.FileDiff{
        .{ .path = "a.zig", .content = "a" ** 1000, .change_type = .modified, .estimated_tokens = 250 },
        .{ .path = "b.zig", .content = "b" ** 1000, .change_type = .modified, .estimated_tokens = 250 },
        .{ .path = "c.zig", .content = "c" ** 4000, .change_type = .modified, .estimated_tokens = 1000 },
    };
    
    var chunks = try diff_processor.chunkFiles(std.testing.allocator, files, 800);
    defer diff_processor.freeChunks(std.testing.allocator, chunks);
    
    // With 800 token limit (10% buffer = 720), should get 2 chunks:
    // Chunk 1: c.zig (1000 tokens) alone
    // Chunk 2: a.zig + b.zig (500 tokens total)
    try std.testing.expectEqual(@as(usize, 2), chunks.len);
}

test "skip lockfiles" {
    const files = &[_]diff_processor.FileDiff{
        .{ .path = "src/main.zig", .content = "...", .change_type = .modified, .estimated_tokens = 100 },
        .{ .path = "package-lock.json", .content = "...", .change_type = .modified, .estimated_tokens = 10000 },
    };
    
    var skipped = std.ArrayList(diff_processor.SkippedFile).init(std.testing.allocator);
    defer skipped.deinit();
    
    var filtered = try diff_processor.filterFiles(
        std.testing.allocator,
        files,
        .{ .max_tokens_per_chunk = 1000, .max_file_tokens = 5000, .skip_lockfiles = true, .skip_binaries = true },
        &skipped,
    );
    defer std.testing.allocator.free(filtered);
    
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqualStrings("src/main.zig", filtered[0].path);
    try std.testing.expectEqual(@as(usize, 1), skipped.items.len);
    try std.testing.expectEqual(diff_processor.SkipReason.lockfile, skipped.items[0].reason);
}

test "parse extraction response" {
    const response =
        \\FILE: src/main.zig
        \\SUMMARY: Added input validation
        \\KEY_CHANGES:
        \\- Added validateInput() function
        \\- Modified processForm() to use validator
        \\IMPACT: HIGH
        \\BREAKING: NO
        \\RATIONALE: Prevents crashes from invalid input
    ;
    
    const expected_files = &[_]diff_processor.FileDiff{
        .{ .path = "src/main.zig", .content = "", .change_type = .modified, .estimated_tokens = 0 },
    };
    
    var extractions = try diff_processor.parseExtractionResponse(
        std.testing.allocator,
        response,
        expected_files,
    );
    defer diff_processor.freeExtractions(std.testing.allocator, extractions);
    
    try std.testing.expectEqual(@as(usize, 1), extractions.len);
    try std.testing.expectEqualStrings("src/main.zig", extractions[0].path);
    try std.testing.expectEqual(.high, extractions[0].impact_level);
    try std.testing.expect(!extractions[0].breaking_change);
}
```

#### 10.2 Integration Test

Create a test with a mock LLM provider:

```zig
test "end-to-end diff processing" {
    // This would require a mock provider that returns predetermined responses
    // to test the full flow without making real API calls
}
```

### Phase 11: Error Handling & Edge Cases (2-3 hours)

#### 11.1 Rate Limit Handling in Parallel Processing

When processing chunks in parallel, rate limits can be hit. Strategy:

1. If a chunk fails with RateLimited, immediately cancel other pending chunks
2. Display error message suggesting:
   - Wait and retry
   - Reduce `max_tokens_per_chunk` in config
   - Reduce number of staged files

#### 11.2 Partial Success Handling

If some chunks succeed and others fail:

```zig
// Instead of failing entirely, we could:
// 1. Log warning about incomplete analysis
// 2. Proceed with partial data
// 3. Note in commit message that some files weren't fully analyzed

// However, per user requirements: "fail entire commit generation"
// So we abort on any chunk failure
```

#### 11.3 Empty Diff Handling

```zig
if (diff.len == 0 or std.mem.trim(u8, diff, " \n\r\t").len == 0) {
    return error.EmptyDiff;
}
```

#### 11.4 All Files Skipped

```zig
if (chunks.len == 0) {
    if (skipped_files.len > 0) {
        // Show helpful message
        std.log.err("All {d} files were skipped:", .{skipped_files.len});
        for (skipped_files) |skipped| {
            std.log.err("  - {s} ({s})", .{ skipped.path, @tagName(skipped.reason) });
        }
        std.log.info("Tip: Adjust chunking.max_file_tokens in config to include large files", .{});
    }
    return error.NoProcessableFiles;
}
```

### Phase 12: Documentation (1-2 hours)

Update `README.md` or create docs explaining:

1. **How chunking works**: Automatic splitting of large diffs by file boundaries
2. **Configuration options**:
   - `max_tokens_per_chunk`: Target size for each LLM request (default: 3500)
   - `max_file_tokens`: Files larger than this are skipped (default: 5000)
   - `skip_lockfiles`: Whether to skip lockfiles entirely (default: true)
   - `skip_binaries`: Whether to skip binary files (default: true)
3. **Impact levels**: How the LLM categorizes changes (critical/high/medium/low)
4. **Troubleshooting**:
   - "All files skipped" error
   - Rate limit issues with parallel processing
   - Large file handling

## File Structure

```
src/
├── diff_processor.zig          # Main module
├── diff_processor_tests.zig    # Unit tests
├── llm.zig                     # Add sendRequest method
├── config.zig                  # Add ChunkingConfig
├── main.zig                    # Update integration
└── ...
```

## Estimated Timeline

- **Phase 1** (Diff parsing): 2-3 hours
- **Phase 2** (Chunking): 2-3 hours
- **Phase 3** (Extraction prompts): 2-3 hours
- **Phase 4** (Response parsing): 3-4 hours
- **Phase 5** (Parallel processing): 3-4 hours
- **Phase 6** (Combining results): 2-3 hours
- **Phase 7** (Final generation): 2 hours
- **Phase 8** (Integration): 2-3 hours
- **Phase 9** (Provider interface): 1-2 hours
- **Phase 10** (Testing): 4-5 hours
- **Phase 11** (Error handling): 2-3 hours
- **Phase 12** (Documentation): 1-2 hours

**Total: ~26-37 hours** of focused implementation work

## Key Design Decisions

1. **No CLI flags**: All configuration via config file for cleaner interface
2. **Fail fast**: Any chunk failure aborts entire commit generation
3. **No caching**: Simpler implementation, always fresh analysis
4. **Parallel processing**: Faster but requires careful rate limit handling
5. **Structured text over JSON**: Easier to debug, LLM-friendly format
6. **Impact-based prioritization**: Critical/high changes appear first in final output
7. **Conservative token estimates**: bytes/4 with 10% safety buffer

## Next Steps

1. Review this plan
2. Decide on implementation approach (all at once or phased)
3. Begin Phase 1 implementation
4. Set up test infrastructure with mock LLM provider

## Open Questions

1. Should we provide a way to preview what files will be skipped before running?
2. Should the final commit message include a note about skipped files?
3. Should we support a "safe mode" that uses sequential processing instead of parallel?
4. What's the maximum number of parallel chunks we should allow (currently 3)?
