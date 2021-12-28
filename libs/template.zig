const std = @import("std");

pub const CONFIG = 
    \\#####################
    \\#  ZED CONFIG FILE  #
    \\#####################
    \\* VAR
    \\$zig.home: ~/tools/zig-macos-x86_64-0.8.1/
    \\
    \\* KEY BINDING
    \\# key: action
    \\F1: @help
    \\C-q: @quit
    \\C-s: @save
    \\
    \\* KEY CODES
    \\# key name: codes
    \\F1:  1b 4f 50
    \\F12: 1b 0a de
    \\
    \\* ACTIONS
    \\# name: command
    \\build: $zig.home/zig build
    \\pull: git pull
    \\
    \\* BUILTIN
    \\# defined builtin functions
    \\@help
    \\@quit
    \\@save
    \\@open filename
    \\@exec command
    \\@goto-line number
;

pub const HELP = 
    \\ HELP
    \\ open Help with F1
    \\ quit zed:  Ctrl-q
    \\ save file: Ctrl-s
;