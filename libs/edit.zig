const std = @import("std");
const math = @import("math.zig");
const files = @import("files.zig");
const config = @import("config.zig");
const term = @import("term.zig");
const mem = std.mem;
const print = std.debug.print;
const assert = std.debug.assert;
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;
const Color = term.Color;
const Scope = term.Scope;
const Position = term.Position;
const Builtin = config.Builtin;
const KeyCode = config.KeyCode;

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
            .content = config.literalToArray(txt, t),
            .length = txt.len,
            .cursor = Position{ .x = 0, .y = 0 },
            .filename = "",
            .modified = false,
            .last_x = 0,
            .page_y = 0,
        };
    }
};

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
    const file = std.fs.cwd().openFile(t.filename, .{ .mode = .read_only }) catch @panic("File open failed!");
    defer file.close();
    t.length = file.getEndPos() catch @panic("file seek error!");
    // extent to multiple of chunk and add one chunk
    const length = math.multipleOf(config.chunk, t.length) + config.chunk;
    t.content = allocator.alloc(u8, length) catch @panic(OOM);
    const bytes_read = file.readAll(t.content) catch @panic("File too large!");
    assert(bytes_read == t.length);
    message = "";
    return t;
}
pub fn saveFile(t: *Text, screen_content: []u8) !void {
    const file = try std.fs.cwd().openFile(t.filename, .{ .mode = .write_only });
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
        conf.content = config.literalToArray(config.templ, conf.content);
        conf.length = config.templ.len;
        saveFile(&conf, screen.content) catch @panic("failed: save file");
    }
    defer allocator.free(conf.content);
    config.parse(conf.content);
    
    var key: KeyCode = undefined;
    var current_text = getCurrentText(&text, &conf);
    bufScreen(current_text, screen.content, key);
    while(key.data[0] != quitKey()) {
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

/// builtin fn
inline fn quitKey() u8 {
    return config.charOf(Builtin.quit, config.ctrlKey('q'));
}

inline fn toggleModus(mode: Mode) void {
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

var enter_filename = false;
const MAX_FILENAME_LENGTH: u8 = 32;
var input_filename = [_]u8{0} ** MAX_FILENAME_LENGTH;
var input_filename_index: u8 = 0;
inline fn writeFilenameChar(char: u8, txt: *Text, screen_content: []u8, screen_index: usize) usize {
    if (input_filename_index < MAX_FILENAME_LENGTH) {
        input_filename[input_filename_index] = char;
        input_filename_index += 1;
        txt.filename = input_filename[0..input_filename_index];
        message = if(files.exists(txt.filename)) "exists!" else "";
        return bufStatusBar(txt, screen_content, screen_index);
    }
    return screen_index;
}
inline fn backspaceFilename(txt: *Text, screen_content: []u8, screen_index: usize) usize {
    if (input_filename_index > 0) {
        input_filename_index -= 1;
        txt.filename = input_filename[0..input_filename_index];
        return bufStatusBar(txt, screen_content, screen_index);
    }
    return screen_index;
}
inline fn filenameEntered(txt: *Text, screen_content: []u8, screen_index: usize, allocator: Allocator) usize {
    if(files.exists(txt.filename)) message = "exists: overwriting!";
    enter_filename = false;
    const file = std.fs.cwd().createFile(txt.filename, .{}) catch @panic("Failed: createFile");
    file.close();
    saveFile(txt, screen_content) catch |err| {
        message = std.fmt.allocPrint(allocator, "Can't save: {s}", .{ err }) catch @panic(OOM);
    };
    return bufStatusBar(txt, screen_content, screen_index);
}

/// builtin fn
fn toggleConfig(text: *Text, cnf: *Text, screen_content: []u8, key: KeyCode) *Text {
    var result = text;
    if (!enter_filename) {
        toggleModus(.conf);
        result = getCurrentText(text, cnf);
        bufScreen(result, screen_content, key);
    }
    return result;
}
/// builtin fn
fn save(txt: *Text, screen_content: []u8, allocator: Allocator) void {
    if (txt.filename.len == 0) {
        enter_filename = true;
    } else {
        saveFile(txt, screen_content) catch |err| {
            message = std.fmt.allocPrint(allocator, "Can't save: {s}", .{ err }) catch @panic(OOM);
        };
    }
}

inline fn isKeyBuiltin(key: KeyCode, builtin: Builtin) bool {
    const tc = config.keyOf(builtin);
    if (key.len == 0 or key.len != tc.len) return false;
    var i: usize = 0;
    while(i < key.len) : (i += 1) {
        if (key.data[i] != tc.data[i]) return false;
    }
    return true;
}

pub fn processKey(text: *Text, cnf: *Text, screen_content: []u8, key: KeyCode, allocator: Allocator) void {
    var t = getCurrentText(text, cnf);
    var i: usize = 0;
    if (isKeyBuiltin(key, Builtin.toggle_config)) {
        t = toggleConfig(text, cnf, screen_content, key);
    } else if (key.len == 1) {
        const c = key.data[0];
        if (c == config.charOf(Builtin.new_line, config.ENTER)) {
            if (enter_filename) {
                i = filenameEntered(t, screen_content, i, allocator);
            } else {
                newLine(t, screen_content, key, allocator);
            }
        } else if (std.ascii.isAlNum(c) or std.ascii.isGraph(c) or c == ' ') {
            if (enter_filename) {
                i = writeFilenameChar(c, t, screen_content, i);
            } else {
                writeChar(c, t, screen_content, key, allocator);
            }
        }
        if (c == config.charOf(Builtin.save, config.ctrlKey('s'))) {
            save(t, screen_content, allocator);
            if (modus == .conf) config.parse(cnf.content);
        }
        if (c == @enumToInt(ControlKey.backspace)) {
            if (enter_filename) {
                i = backspaceFilename(t, screen_content, i);
            } else {
                backspace(t, screen_content, key);
            }
        }
    } else if (key.len == 3) {
        if (key.data[0] == 0x1b and key.data[1] == 0x5b and key.data[2] == 0x41) 
            cursorUp(t, screen_content, key);
        if (key.data[0] == 0x1b and key.data[1] == 0x5b and key.data[2] == 0x42) 
            cursorDown(t, screen_content, key);
        if (key.data[0] == 0x1b and key.data[1] == 0x5b and key.data[2] == 0x43) 
            cursorRight(t, screen_content, key);
        if (key.data[0] == 0x1b and key.data[1] == 0x5b and key.data[2] == 0x44) 
            cursorLeft(t, screen_content, key);
    }

    if (key.len > 0) {
        writeKeyCodes(t, screen_content, i, key);
    }
}

var themeForeground = Color.cyan;
var themeBackground = Color.blue;
var themeHighlight = Color.white;
var themeWarn = Color.yellow;
var themeError = Color.red;
fn bufMenuBarMode(screen_content: []u8, screen_index: usize) usize {
    return term.bufAttributes(Scope.foreground, themeForeground, 
        Scope.background, themeBackground, screen_content, screen_index);
}
fn bufMenuBarHighlightMode(screen_content: []u8, screen_index: usize) usize {
    return term.bufAttributes(Scope.foreground, themeHighlight, Scope.background, themeBackground, screen_content, screen_index);
}
fn bufStatusBarHighlightMode(screen_content: []u8, screen_index: usize) usize {
    return term.bufAttributes(Scope.foreground, themeHighlight, 
        Scope.background, themeBackground, screen_content, screen_index);
}
fn bufStatusBarMode(screen_content: []u8, screen_index: usize) usize {
    return term.bufAttributes(Scope.foreground, themeForeground, 
        Scope.background, themeBackground, screen_content, screen_index);
}
fn repeatChar(char: u8, count: u16) void {
    var i: u8 = 0;
    while(i<count) : (i += 1) {
        term.writeByte(char);
    }
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
fn bufTextCursor(txt: *Text, screen_content: []u8, screen_index: usize) usize {
    var screen_pos = positionOnScreen(txt.cursor, txt.page_y);
    if (screen_pos.x >= config.width) {
        screen_pos.x = config.width - 1;
    }
    return term.bufCursor(screen_pos, screen_content, screen_index);
}
fn bufCursor(txt: *Text, screen_content: []u8, screen_index: usize) usize {
    return bufTextCursor(txt, screen_content, screen_index);
}
fn setTextCursor(pos: Position, page_y: usize, allocator: Allocator) void {
    term.setCursor(positionOnScreen(pos, page_y), allocator);
}

inline fn modifiedChar(text: *Text) []const u8 {
    return if (text.filename.len > 0 and text.modified and !enter_filename) "*" else "";
}

inline fn filenameCursorPosition(text_cursor: Position) Position {
    return Position{ 
        .x = math.digits(usize, text_cursor.y) + math.digits(usize, text_cursor.x) + input_filename_index + 4, 
        .y = config.height - 1
    };
}

pub var message: []const u8 = "READY.";
inline fn bufStatusBar(txt: *Text, screen_content: []u8, screen_index: usize) usize {
    var i = bufStatusBarMode(screen_content, screen_index);
    i = term.bufCursor(Position{ .x = 0, .y = config.height - 1}, screen_content, i);

    screen_content[i] = 'L'; i += 1;
    i = term.bufAttribute(Scope.foreground, themeHighlight, screen_content, i);
    const row = std.fmt.bufPrint(screen_content[i..], "{d}", .{txt.cursor.y + 1}) catch @panic(OOM);
    i += row.len;
    i = term.bufAttribute(Scope.foreground, themeForeground, screen_content, i);
    screen_content[i] = ':'; i += 1;
    screen_content[i] = 'C'; i += 1;
    i = term.bufAttribute(Scope.foreground, themeHighlight, screen_content, i);
    const col = std.fmt.bufPrint(screen_content[i..], "{d} ", .{txt.cursor.x + 1}) catch @panic(OOM);
    i += col.len;

    const filename = std.fmt.bufPrint(screen_content[i..], "{s}{s} ", 
        .{txt.filename, modifiedChar(txt)}) catch @panic(OOM);
    i += filename.len;
    i = term.bufAttribute(Scope.foreground, themeWarn, screen_content, i);
    const msg = std.fmt.bufPrint(screen_content[i..], "{s}", .{message}) catch @panic(OOM);
    i += msg.len;
    const offset = config.width - keyCodeOffset;
    i = term.bufWriteRepeat(' ', offset - 3 - row.len - col.len - filename.len - msg.len, screen_content, i);

    i = term.bufAttribute(Scope.foreground, themeForeground, screen_content, i);
    i = term.bufWrite("key code:            ", screen_content, i);
    return term.bufCursor(Position{ .x = offset, .y = config.height - 1}, screen_content, i);
}
test "endOfPageIndex" {
    var t = [_]u8{0} ** 5;
    var txt = Text.forTest("", &t);
    try expect(endOfPageIndex(&txt) == 0);

    txt.content = config.literalToArray("a", &t);
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
    var i = term.bufAttributeMode(term.Mode.reset, term.Scope.foreground, themeForeground, screen_content, screen_index);
    return term.bufFillScreen(conf, screen_content, i, config.width, textHeight());
}
fn bufScreen(txt: *Text, screen_content: ?[]u8, key: KeyCode) void {
    if (screen_content != null) {
        var i = bufMenuBar(screen_content.?, 0);
        i = bufText(txt, screen_content.?, i);
        i = bufStatusBar(txt, screen_content.?, i);
        writeKeyCodes(txt, screen_content.?, i, key);
    }
}

fn writeKeyCodes(txt: *Text, screen_content: []u8, screen_index: usize, key: KeyCode) void {
    assert(screen_content.len > screen_index);
    var i = bufKeyCodes(key, Position{
        .x = config.width - keyCodeOffset + 10, 
        .y = config.height - 1}, 
        screen_content, screen_index);
    if (enter_filename) {
        i = term.bufCursor(filenameCursorPosition(txt.cursor), screen_content, i);
    } else {
        i = bufTextCursor(txt, screen_content, i);
    }
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

fn cursorLeft(txt: *Text, screen_content: ?[]u8, key: KeyCode) void {
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
    const key = KeyCode{ .data = [_]u8{ 0x61, 0x00, 0x00, 0x00}, .len = 1};
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 0);
    cursorRight(&txt, null, key);
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 0);

    txt.content = config.literalToArray("a", &t);
    txt.length = 1;
    cursorRight(&txt, null, key);
    try expect(txt.cursor.x == 1);
    try expect(txt.cursor.y == 0);

    txt.content = config.literalToArray("a\n", &t);
    txt.length = 2;
    txt.cursor.x = 1;
    txt.cursor.y = 0;
    try expect(txt.rowLength(0) == 2);
    cursorRight(&txt, null, key);
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 1);
}
fn cursorRight(t: *Text, screen_content: ?[]u8, key: KeyCode) void {
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
fn newLine(t: *Text, screen_content: ?[]u8, key: KeyCode, allocator: Allocator) void {
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
    const key = KeyCode{ .data = [_]u8{ 0x61, 0x00, 0x00, 0x00}, .len = 1};
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

    allocator.free(txt.content);
}
fn writeChar(char: u8, t: *Text, screen_content: ?[]u8, key: KeyCode, allocator: Allocator) void {
    extendBufferIfNeeded(t, allocator);
    const i = t.cursorIndex();
    
    if (i < t.length) shiftRight(t, t.cursor);
    t.content[i] = char;
    t.modified = true;
    t.length += 1;
    cursorRight(t, screen_content, key);
}
fn backspace(t: *Text, screen_content: ?[]u8, key: KeyCode) void {
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
    var t = [_]u8{0} ** 4;
    var txt = Text.forTest("a\na\n", &t);
    txt.cursor = Position{.x=0, .y=2};
    try expect(txt.cursorIndex() == 4);
    const key = KeyCode{ .data = [_]u8{ 0x1b, 0x5b, 0x41, 0x00}, .len = 3};
    cursorUp(&txt, null, key);
    try expect(txt.cursorIndex() == 2);
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 1);
}
fn cursorUp(t: *Text, screen_content: ?[]u8, key: KeyCode) void {
    _ = t.cursorIndex();
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

fn cursorDown(t: *Text, screen_content: ?[]u8, key: KeyCode) void {
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

const NOBR = "Failed: bufPrint";
fn bufKeyCodes(key: KeyCode, pos: Position, screen_content: []u8, screen_index: usize) usize {
    var i = bufStatusBarHighlightMode(screen_content, screen_index);
    i = term.bufCursor(pos, screen_content, i);
    i = term.bufWrite("           ", screen_content, i);
    i = term.bufAttribute(Scope.foreground, themeHighlight, screen_content, i);
    i = term.bufCursor(pos, screen_content, i);
    if(key.len == 0) {
        return i;
    }
    if(key.len == 1) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x}", .{key.data[0]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 2) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x} {x}", .{key.data[0], key.data[1]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 3) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x} {x} {x}", .{key.data[0], key.data[1], key.data[2]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 4) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x} {x} {x} {x}", .{key.data[0], key.data[1], key.data[2], key.data[3]}) catch @panic(NOBR);
        i += written.len;
    }
    return term.bufWrite(term.RESET_MODE, screen_content, i);
}