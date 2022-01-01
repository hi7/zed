const std = @import("std");

pub const CONFIG = 
    \\#####################
    \\#  ZED CONFIG FILE  #
    \\#####################
    \\* VAR
    \\$zig.home: ~/tools/zig-linux-x86_64-0.8.1/
    \\
    \\* KEY CODES
    \\# key name: codes
    \\F1:  1b 5b 5b 41
    \\F12: 1b 0a de
    \\
    \\* KEY BINDING
    \\# key: action
    \\F1: @help
    \\C-q: @quit
    \\C-s: @save
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