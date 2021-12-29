const std = @import("std");
const math = @import("math.zig");
const files = @import("files.zig");
const config = @import("config.zig");
const term = @import("term.zig");
const mem = std.mem;
const print = std.debug.print;
const assert = std.debug.assert;
const expect = std.testing.expect;
const Allocator = *std.mem.Allocator;
const Color = term.Color;
const Scope = term.Scope;
const Position = term.Position;

const NEW_LINE = 0x0a;
const MENU_BAR_HEIGHT = 1;
const STATUS_BAR_HEIGHT = 1;

// Errors
const OOM = "Out of memory error";

const keyCodeOffset = 21;

pub const Mode = enum { edit, conf };
var old_modus: Mode = undefined;
var modus: Mode = .edit;

test "indexOfRowStart" {
    var t = [_]u8{0} ** 5;
    try expect(Text.forTest("", &t).indexOfRowStart(0) == 0);
    try expect(Text.forTest("", &t).indexOfRowStart(1) == 0);
    try expect(Text.forTest("a", &t).indexOfRowStart(0) == 0);
    try expect(Text.forTest("\n", &t).indexOfRowStart(0) == 0);
    try expect(Text.forTest("\n", &t).indexOfRowStart(1) == 1);
    try expect(Text.forTest("\n\n", &t).indexOfRowStart(1) == 1);
    try expect(Text.forTest("a\n", &t).indexOfRowStart(1) == 2);
    try expect(Text.forTest("a\na", &t).indexOfRowStart(1) == 2);
    try expect(Text.forTest("a\n\na", &t).indexOfRowStart(2) == 3);
}
test "indexOf" {
    var t = [_]u8{0} ** 5;
    try expect(Text.forTest("", &t).indexOf(Position{.x=0, .y=0}) == 0);
    try expect(Text.forTest("a", &t).indexOf(Position{.x=1, .y=0}) == 1);
    try expect(Text.forTest("a", &t).indexOf(Position{.x=2, .y=0}) == 1);
    try expect(Text.forTest("a", &t).indexOf(Position{.x=0, .y=0}) == 0);
    try expect(Text.forTest("ab", &t).indexOf(Position{.x=1, .y=0}) == 1);
    try expect(Text.forTest("a\n", &t).indexOf(Position{.x=1, .y=0}) == 1);
    try expect(Text.forTest("a\nb", &t).indexOf(Position{.x=0, .y=1}) == 2);
    try expect(Text.forTest("a\n\nb", &t).indexOf(Position{.x=1, .y=2}) == 4);
    try expect(Text.forTest("a\nb\n", &t).indexOf(Position{.x=0, .y=2}) == 4);
    try expect(Text.forTest("a\n\nb", &t).indexOf(Position{.x=0, .y=2}) == 3);
    try expect(Text.forTest("a\nb\nc", &t).indexOf(Position{.x=0, .y=2}) == 4);
}
test "rowLength" {
    var t = [_]u8{0} ** 5;
    try expect(Text.forTest("", &t).rowLength(0) == 0);
    try expect(Text.forTest("a", &t).rowLength(0) == 1);
    try expect(Text.forTest("ab", &t).rowLength(0) == 2);
    try expect(Text.forTest("\n", &t).rowLength(0) == 1);
    try expect(Text.forTest("\n", &t).rowLength(1) == 0);
    try expect(Text.forTest("\na", &t).rowLength(0) == 1);
    try expect(Text.forTest("\na", &t).rowLength(1) == 1);
    try expect(Text.forTest("\na\n", &t).rowLength(1) == 2);
    try expect(Text.forTest("\n\n", &t).rowLength(1) == 1);
    try expect(Text.forTest("\n\n", &t).rowLength(2) == 0);
    try expect(Text.forTest("\n\na", &t).rowLength(2) == 1);
}
test "new" {
    var t = [_]u8{0} ** 5;
    try expect(Text.forTest("", &t).length == 0);
    try expect(Text.forTest("a", &t).length == 1);
}
const Text = struct {
    content: []u8,
    length: usize,
    cursor: Position,
    filename: []const u8,
    modified: bool,
    last_x: usize,
    page_y: usize,
    fn rows(self: *const Text) usize {
        var n: usize = 0;
        var i: usize = 0;
        while (i < self.length) : (i+=1) {
            if(self.content[i] == NEW_LINE) {
                n+=1;
            }
        }
        return n;
    }
    /// return the index of first charactern in given line
    fn indexOfRowStart(self: *const Text, line: usize) usize {
        if (line == 0) return 0;

        var n: usize = 0;
        var i: usize = 0;
        while (i < self.length) : (i+=1) {
            if(self.content[i] == NEW_LINE) {
                n+=1;
                if (n == line) return i + 1;
            }
        }
        if (n == 0) return 0;
        if (self.content[i] == NEW_LINE) return i + 1;
        if (n < line) return self.length;
        @panic("no more lines!");
    }
    fn indexOfRowEnd(self: *const Text, line: usize) usize {
        return self.indexOfRowStart(line) + self.rowLength(line);
    }
    fn nextNewLine(self: *const Text, index: usize) usize {
        if (self.length == 0) return 0;

        var i = index;
        while (i < self.length) : (i+=1) {
            if(self.content[i] == NEW_LINE) {
                return i + 1;
            }
        }
        return self.length;
    }
    fn rowLength(self: *const Text, row: usize) usize {
        if (self.length == 0) return 0;

        const row_start = self.indexOfRowStart(row);
        const row_end = self.nextNewLine(row_start);
        if (row_end > row_start) return row_end - row_start;
        return 0;
    }
    fn indexOf(self: *Text, pos: Position) usize {
        if (self.length == 0) return 0;

        var i = self.indexOfRowStart(pos.y);
        const row_length = self.nextNewLine(i) - i;
        if (pos.x > row_length) {
            return i + row_length;
        }
        return i + pos.x;
    }
    fn cursorIndex(self: *Text) usize {
        return self.indexOf(self.cursor);
    }
    fn new(txt: []u8, len: usize) Text {
        assert(len <= txt.len);
        return Text {
            .content = txt,
            .length = len,
            .cursor = Position{ .x = 0, .y = 0 },
            .filename = "",
            .modified = false,
            .last_x = 0,
            .page_y = 0,
        };
    }
    fn copy(orig: Text, txt: []u8) Text {
        return Text {
            .content = txt,
            .cursor = Position{ .x = orig.cursor.x, .y = orig.cursor.y },
            .length = orig.length,
            .filename = orig.filename,
            .modified = orig.modified,
            .last_x = orig.last_x,
            .page_y = orig.page_y,
        };
    }
    fn forTest(comptime txt: []const u8, t: []u8) Text {
        return Text {
            .content = literalToArray(txt, t),
            .length = txt.len,
            .cursor = Position{ .x = 0, .y = 0 },
            .filename = "",
            .modified = false,
            .last_x = 0,
            .page_y = 0,
        };
    }
};
test "literalToArray" {
    var result = [_]u8{0} ** 3;
    var r = literalToArray("abc", &result);
    try expect(mem.eql(u8, "abc", r));
}
fn literalToArray(comptime source: []const u8, dest: []u8) []u8 {
    mem.copy(u8, dest, source);

    return dest;
}

const ScreenBuffer = struct {
    content: []u8,
    index: usize,
    fn new() ScreenBuffer {
        return ScreenBuffer {
            .content = "",
            .index = 0,
        };
    }
};

pub const ControlKey = enum(u8) {
    backspace = 0x7f, 
    pub fn isControlKey(char: u8) bool {
        inline for (std.meta.fields(ControlKey)) |field| {
            if (char == field.value) return true;
        }
        return false;
    }
};

pub fn loadFile(txt: Text, filepath: []const u8, allocator: Allocator) Text {
    var t = txt;
    t.filename = filepath;
    const file = std.fs.cwd().openFile(t.filename, .{ .read = true }) catch @panic("File open failed!");
    defer file.close();
    t.length = file.getEndPos() catch @panic("file seek error!");
    // extent to multiple of chunk and add one chunk
    const expected_length = math.multipleOf(config.chunk, t.length) + config.chunk;
    t.content = allocator.alloc(u8, expected_length) catch @panic(OOM);
    const bytes_read = file.readAll(t.content) catch @panic("File too large!");
    assert(bytes_read == t.length);
    message = "";
    return t;
}
pub fn saveFile(t: *Text, screen_content: []u8) !void {
    if (modus == .edit and t.filename.len > 0) {
        const file = try std.fs.cwd().openFile(t.filename, .{ .write = true });
        defer file.close();
        _ = try file.write(t.content[0..t.length]);
        _ = try file.setEndPos(t.length);
        const stat = try file.stat();
        assert(stat.size == t.length);
        t.modified = false;
        var size = bufStatusBar(t, screen_content, 0);
        size = bufCursor(t, screen_content, size);
        term.write(screen_content[0..size]);
    }
}
pub fn loop(filepath: ?[]u8, allocator: Allocator) !void {
    var text = Text.new("", 0);
    var conf = Text.new("", 0);
    var screen = ScreenBuffer.new();
    _ = term.updateWindowSize();
    if(filepath != null) text = loadFile(text, filepath.?, allocator);
    defer allocator.free(text.content);

    // multiple times the space for long utf codes and ESC-Seq.
    screen.content = allocator.alloc(u8, config.width * config.height * 4) catch @panic(OOM);
    defer allocator.free(screen.content);
    term.rawMode(5);
    term.write(term.CLEAR_SCREEN);

    const home_config_file = files.homeFilePath(allocator);
    if(files.exists(home_config_file)) {
        conf = loadFile(conf, home_config_file, allocator);
    } else {
        if (!files.exists(files.home_path)) {
            message = "DIR";
            std.fs.makeDirAbsolute(files.home_path) catch @panic("Failed: makeDirAbsolute");
        }

        const cf = std.fs.createFileAbsolute(home_config_file, .{}) catch @panic("Failed: createFileAbsolute");
        cf.close();
        conf.filename = home_config_file;
        conf.content = allocator.alloc(u8, config.templ.len) catch @panic(OOM);
        conf.content = literalToArray(config.templ, conf.content);
        conf.length = config.templ.len;
        saveFile(&conf, screen.content) catch @panic("failed: save file");
    }
    defer allocator.free(conf.content);

    var key: term.KeyCode = undefined;
    var current_text = getCurrentText(&text, &conf);
    bufScreen(current_text, screen.content, key);
    while(key.code[0] != term.ctrlKey('q')) {
        key = term.readKey();
        if(key.len > 0) {
            processKey(&text, &conf, screen.content, key, allocator);
        }
        if (term.updateWindowSize()) bufScreen(current_text, screen.content, key);
    }

    term.write(term.RESET_MODE);
    term.cookedMode();
    term.write(term.CLEAR_SCREEN);
    term.write(term.CURSOR_HOME);

    files.free(allocator);
}

inline fn setModus(mode: Mode) void {
    if (modus != mode) {
        old_modus = modus;
        modus = mode;
    } else {
        modus = old_modus;
        old_modus = mode;
    }
}

inline fn getCurrentText(text: *Text, cnf: *Text) *Text {
    return if (modus == .edit) text else cnf;
}

pub fn processKey(text: *Text, cnf: *Text, screen_content: []u8, key: term.KeyCode, allocator: Allocator) void {
    var t = getCurrentText(text, cnf);
    var i: usize = 0;
    if (key.len == 1) {
        const c = key.code[0];
        if (c == 0x0d) { // new line
            newLine(t, screen_content, key, allocator);
        } else if (std.ascii.isAlNum(c) or std.ascii.isGraph(c) or c == ' ') {
            writeChar(c, t, screen_content, key, allocator);
        }
        if (c == term.ctrlKey('s')) {
            saveFile(t, screen_content) catch |err| {
                message = std.fmt.allocPrint(allocator, "Can't save: {s}", .{ err }) catch @panic(OOM);
                return;
            };
        }
        if (c == @enumToInt(ControlKey.backspace)) backspace(t, screen_content, key);
    } else if (key.len == 3) {
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x41) 
            cursorUp(t, screen_content, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x42) 
            cursorDown(t, screen_content, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x43) 
            cursorRight(t, screen_content, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x44) 
            cursorLeft(t, screen_content, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x4f and key.code[2] == 0x50) {
            setModus(.conf);
            bufScreen(getCurrentText(text, cnf), screen_content, key);
        }
    }
    if (key.len > 0) {
        writeKeyCodes(t, screen_content, 0, key);
    }
}

var themeForegroundColor = Color.cyan;
var themeBackgroundColor = Color.blue;
var themeHighlight = Color.white;
fn bufMenuBarMode(screen_content: []u8, screen_index: usize) usize {
    return term.bufAttributes(Scope.foreground, themeForegroundColor, 
        Scope.background, themeBackgroundColor, screen_content, screen_index);
}
fn bufMenuBarHighlightMode(screen_content: []u8, screen_index: usize) usize {
    return term.bufAttributes(Scope.foreground, themeHighlight, Scope.background, themeBackgroundColor, screen_content, screen_index);
}
fn bufStatusBarMode(screen_content: []u8, screen_index: usize) usize {
    return term.bufAttributes(Scope.foreground, themeHighlight, 
        Scope.background, themeBackgroundColor, screen_content, screen_index);
}
fn repeatChar(char: u8, count: u16) void {
    var i: u8 = 0;
    while(i<count) : (i += 1) {
        term.writeByte(char);
    }
}

fn showMessage(message: []const u8, allocator: Allocator) void {
    setStatusBarMode(allocator);
    term.setCursor(50, height - 1, allocator);
    term.write(message);
    term.resetMode();
}

fn bufShortCut(key: []const u8, label: []const u8, screen_content: []u8, screen_index: usize) usize {
    var i = bufMenuBarHighlightMode(screen_content, screen_index);
    i = term.bufWrite(key, screen_content, i);
    i = bufMenuBarMode(screen_content, i);
    return term.bufWrite(label, screen_content, i);
}
inline fn bufMenuBar(screen_content: []u8, screen_index: usize) usize {
    var i = term.bufWrite(term.CURSOR_HOME, screen_content, screen_index);
    if (modus == .edit) {
        i = bufShortCut("F1", " Config ", screen_content, i);
    }
    if (modus == .conf) {
        i = bufShortCut("F1", " go back", screen_content, i);
    }
    i = bufMenuBarMode(screen_content, i);
    i = term.bufWriteRepeat(' ', config.width - 10 - 25, screen_content, i);


    i = bufShortCut("S", "ave: Ctrl-s ", screen_content, i);
    i = bufShortCut("Q", "uit: Ctrl-q", screen_content, i);
    return i;
}
fn fileColor(changed: bool) Color {
    return if(changed) Color.yellow else Color.white;
}

inline fn positionOnScreen(pos: Position, page_y: usize) Position {
    return Position{ 
        .x = pos.x, 
        .y = MENU_BAR_HEIGHT + pos.y - page_y,
    };
}
fn bufTextCursor(pos: Position, page_y: usize, screen_content: []u8, screen_index: usize) usize {
    var screen_pos = positionOnScreen(pos, page_y);
    if (screen_pos.x >= config.width) {
        screen_pos.x = config.width - 1;
    }
    return term.bufCursor(screen_pos, screen_content, screen_index);
}
fn bufCursor(txt: *Text, screen_content: []u8, screen_index: usize) usize {
    return bufTextCursor(txt.cursor, txt.page_y, screen_content, screen_index);
}
fn setTextCursor(pos: Position, page_y: usize, allocator: Allocator) void {
    term.setCursor(positionOnScreen(pos, page_y), allocator);
}

inline fn mod(text: *Text) []const u8 {
    return if (text.filename.len > 0 and text.modified) "*" else "";
}

pub var message: []const u8 = "READY.";
inline fn bufStatusBar(txt: *Text, screen_content: []u8, screen_index: usize) usize {
    var i = bufStatusBarMode(screen_content, screen_index);
    i = term.bufCursor(Position{ .x = 0, .y = config.height - 1}, screen_content, i);
    const stats = std.fmt.bufPrint(screen_content[i..], "L{d}:C{d} {s}{s} {s}", 
        .{txt.cursor.y + 1, txt.cursor.x + 1, txt.filename, mod(txt), message}) catch @panic(OOM);
    i += stats.len;
    const offset = config.width - keyCodeOffset;
    i = term.bufWriteRepeat(' ', offset - stats.len, screen_content, i);

    i = term.bufCursor(Position{ .x = offset, .y = config.height - 1}, screen_content, i);
    return term.bufWrite("key code:            ", screen_content, i);
}
test "endOfPageIndex" {
    var t = [_]u8{0} ** 5;
    var txt = Text.forTest("", &t);
    try expect(endOfPageIndex(&txt) == 0);

    txt.content = literalToArray("a", &t);
    txt.length = 1;
    try expect(endOfPageIndex(&txt) == 1);
}
inline fn textHeight() usize {
    return config.height - MENU_BAR_HEIGHT - STATUS_BAR_HEIGHT;
}
inline fn endOfPageIndex(txt: *Text) usize {
    return txt.indexOfRowEnd(txt.page_y + textHeight() - 1);
}
inline fn bufText(txt: *Text, screen_content: []u8, screen_index: usize) usize {
    assert(screen_content.len > screen_index);
    var i = term.bufWrite(term.CURSOR_SHOW, screen_content, screen_index);
    i = term.bufWrite(term.RESET_MODE, screen_content, i);
    const sop = txt.indexOfRowStart(txt.page_y);
    const eop = endOfPageIndex(txt);
    const page = txt.content[sop..eop];
    return term.bufFillScreen(page, screen_content, i, config.width, textHeight());
}
inline fn bufConf(conf: []const u8, screen_content: []u8, screen_index: usize) usize {
    assert(screen_content.len > screen_index);
    // var i = term.bufWrite(term.CURSOR_HIDE, screen_content, screen_index);
    var i = term.bufAttributeMode(term.Mode.reset, term.Scope.foreground, themeForegroundColor, screen_content, screen_index);
    return term.bufFillScreen(conf, screen_content, i, config.width, textHeight());
}
fn bufScreen(txt: *Text, screen_content: ?[]u8, key: term.KeyCode) void {
    if (screen_content != null) {
        var i = bufMenuBar(screen_content.?, 0);
        i = bufText(txt, screen_content.?, i);
        i = bufStatusBar(txt, screen_content.?, i);
        writeKeyCodes(txt, screen_content.?, i, key);
    }
}

fn writeKeyCodes(txt: *Text, screen_content: []u8, screen_index: usize, key: term.KeyCode) void {
    assert(screen_content.len > screen_index);
    var i = bufKeyCodes(key, Position{
        .x = config.width - keyCodeOffset + 10, 
        .y = config.height - 1}, 
        screen_content, screen_index);
    i = bufTextCursor(txt.cursor, txt.page_y, screen_content, i);
    term.write(screen_content[0..i]);
}

fn shiftLeft(t: *Text, pos: Position) void {
    var i = t.indexOf(pos);
    while(i < t.length) : (i += 1) {
        t.content[i-1] = t.content[i];
    }
}
fn shiftRight(t: *Text, pos: Position) void {
    var i = t.length;
    var ci = t.indexOf(pos);
    while(i > ci) : (i -= 1) {
        t.content[i] = t.content[i-1];
    }
}

fn extendBuffer(t: *Text, allocator: Allocator) void {
    const length = math.multipleOf(config.chunk, t.content.len) + config.chunk;
    var new_content = allocator.alloc(u8, length) catch @panic(OOM);

    const i = t.cursorIndex();
    if (i < t.content.len) {
        mem.copy(u8, new_content[0..i - 1], t.content[0..i - 1]);
    }
    allocator.free(t.content);
    t.content = new_content;
}
fn extendBufferIfNeeded(t: *Text, allocator: Allocator) void {
    if(t.content.len == 0 or t.cursorIndex() >= t.content.len) {
        extendBuffer(t, allocator);
    }
}

fn cursorLeft(txt: *Text, screen_content: ?[]u8, key: term.KeyCode) void {
    var t = txt;
    var update = false;
    if (t.cursor.x > 0) {
        t.cursor.x -= 1;
        t.last_x = t.cursor.x;
        update = true;
    } else {
        if (t.cursor.y > 0) {
            t.cursor.x = t.rowLength(t.cursor.y - 1) - 1;
            t.cursor.y -= 1;
            if (t.page_y > 0 and positionOnScreen(t.cursor, t.page_y).y == 0) {
                scrollDown(t);
            }
            update = true;
        }
    }
    if (update) {
        t.last_x = t.cursor.x;
        bufScreen(t, screen_content, key);
    }
}
test "cursorRight" {
    var t = [_]u8{0} ** 5;
    var txt = Text.forTest("", &t);
    var screen_content = [_]u8{0} ** 9000;
    const key = term.KeyCode{ .code = [_]u8{ 0x61, 0x00, 0x00, 0x00}, .len = 1};
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 0);
    cursorRight(&txt, null, key);
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 0);

    txt.content = literalToArray("a", &t);
    txt.length = 1;
    cursorRight(&txt, null, key);
    try expect(txt.cursor.x == 1);
    try expect(txt.cursor.y == 0);

    txt.content = literalToArray("a\n", &t);
    txt.length = 2;
    txt.cursor.x = 1;
    txt.cursor.y = 0;
    try expect(txt.rowLength(0) == 2);
    cursorRight(&txt, null, key);
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 1);
}
fn cursorRight(t: *Text, screen_content: ?[]u8, key: term.KeyCode) void {
    if (t.length == 0) return;

    if (t.cursor.x < t.rowLength(t.cursor.y)) {
        if (t.content[t.cursorIndex()] == NEW_LINE) {
            t.cursor.x = 0;
            t.cursor.y += 1;
        } else {
            t.cursor.x += 1;
        }
        const pos = positionOnScreen(t.cursor, t.page_y);
        t.last_x = pos.x;
        if (pos.y == config.height - MENU_BAR_HEIGHT) {
            scrollUp(t);
        }
        bufScreen(t, screen_content, key);
    }
}
fn newLine(t: *Text, screen_content: ?[]u8, key: term.KeyCode, allocator: Allocator) void {
    extendBufferIfNeeded(t, allocator);
    var i = t.cursorIndex();
    if (i < t.length) shiftRight(t, t.cursor);
    t.content[i] = NEW_LINE;
    t.length += 1;
    cursorRight(t, screen_content, key);
    t.modified = true;
    bufScreen(t, screen_content, key);
}
test "writeChar" {
    const allocator = std.testing.allocator;
    var t = [_]u8{0} ** 5;
    var txt = Text.forTest("", &t);
    const key = term.KeyCode{ .code = [_]u8{ 0x61, 0x00, 0x00, 0x00}, .len = 1};
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 0);
    writeChar('a', &txt, null, key, allocator);
    try expect(txt.length == 1);
    try expect(txt.content[0] == 'a');
    try expect(txt.cursor.x == 1);
    try expect(txt.cursor.y == 0);

    writeChar('b', &txt, null, key, allocator);
    try expect(txt.length == 2);
    try expect(txt.content[1] == 'b');
}
fn writeChar(char: u8, t: *Text, screen_content: ?[]u8, key: term.KeyCode, allocator: Allocator) void {
    extendBufferIfNeeded(t, allocator);
    const i = t.cursorIndex();
    
    if (i < t.length) shiftRight(t, t.cursor);
    t.content[i] = char;
    t.modified = true;
    t.length += 1;
    cursorRight(t, screen_content, key);
}
fn backspace(t: *Text, screen_content: ?[]u8, key: term.KeyCode) void {
    if (t.cursorIndex() > 0) {
        if (t.cursor.x == 0) {
            const pos = t.cursor;
            cursorLeft(t, null, key);
            shiftLeft(t, pos);
        } else {
            shiftLeft(t, t.cursor);
            cursorLeft(t, null, key);
        }
        t.modified = true;
        t.length -= 1;
        bufScreen(t, screen_content, key);
    }
}

fn toLastX(txt: *Text, index: usize) usize {
    return math.min(usize, index + txt.last_x, nextBreak(txt, index, 1) - 1);
}
test "scrollDown" {
    var t = [_]u8{0} ** 5;
    var txt = Text.forTest("a\nb\nc", &t);
    txt.page_y = 1;
    scrollDown(&txt);
    try expect(txt.page_y == 0);
}
fn scrollDown(t: *Text) void {
    if (t.page_y > 0) {
        t.page_y -= 1;
    }
}
test "scrollUp" {
    var t = [_]u8{0} ** 5;
    var txt = Text.forTest("a\nb\nc", &t);
    scrollUp(&txt);
    try expect(txt.page_y == 1);
}
fn scrollUp(t: *Text) void {
    if (t.page_y < t.rows()) {
        t.page_y += 1;
    }
}

test "cursorUp" {
    const allocator = std.testing.allocator;
    var t = [_]u8{0} ** 4;
    var txt = Text.forTest("a\na\n", &t);
    txt.cursor = Position{.x=0, .y=2};
    try expect(txt.cursorIndex() == 4);
    var screen_content = [_]u8{0} ** 9000;
    const key = term.KeyCode{ .code = [_]u8{ 0x1b, 0x5b, 0x41, 0x00}, .len = 3};
    cursorUp(&txt, null, key);
    try expect(txt.cursorIndex() == 2);
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 1);
}
fn cursorUp(t: *Text, screen_content: ?[]u8, key: term.KeyCode) void {
    var i = t.cursorIndex();
    if (t.cursor.y > 0) {
        if (positionOnScreen(t.cursor, t.page_y).y == MENU_BAR_HEIGHT and t.page_y > 0) {
            scrollDown(t);
        }
        t.cursor.y -= 1;
        if(t.rowLength(t.cursor.y) - 1 < t.last_x) {
            t.cursor.x = t.rowLength(t.cursor.y) - 1;
        } else {
            t.cursor.x = t.last_x;
        }
        bufScreen(t, screen_content, key);
    }
}

fn cursorDown(t: *Text, screen_content: ?[]u8, key: term.KeyCode) void {
    if (t.cursor.y < t.rows()) {
        t.cursor.y += 1;
        const row_len = t.rowLength(t.cursor.y);
        if (row_len == 0) {
            t.cursor.x = 0;
        } else if (t.indexOf(Position{.x=t.last_x, .y=t.cursor.y}) == t.length) {
            t.cursor.x = row_len;
        } else if(row_len - 1 < t.last_x) {
            t.cursor.x = row_len - 1;
        } else {
            t.cursor.x = t.last_x;
        }

        if (positionOnScreen(t.cursor, t.page_y).y == config.height - MENU_BAR_HEIGHT and t.page_y < t.rows()) {
            scrollUp(t);
        }
        bufScreen(t, screen_content, key);
    }
}

const NOBR = "NoBufPrint";
fn bufKeyCodes(key: term.KeyCode, pos: Position, screen_content: []u8, screen_index: usize) usize {
    var i = bufStatusBarMode(screen_content, screen_index);
    i = term.bufCursor(pos, screen_content, i);
    i = term.bufWrite("           ", screen_content, i);
    i = term.bufAttribute(Scope.foreground, themeForegroundColor, screen_content, i);
    i = term.bufCursor(pos, screen_content, i);
    if(key.len == 0) {
        return i;
    }
    if(key.len == 1) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x}", .{key.code[0]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 2) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x} {x}", .{key.code[0], key.code[1]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 3) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x} {x} {x}", .{key.code[0], key.code[1], key.code[2]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 4) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x} {x} {x} {x}", .{key.code[0], key.code[1], key.code[2], key.code[3]}) catch @panic(NOBR);
        i += written.len;
    }
    return term.bufWrite(term.RESET_MODE, screen_content, i);
}