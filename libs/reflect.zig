const std = @import("std");
const print = std.debug.print;

pub fn showType(comptime T: type, only_pub: bool) void {
    const info = @typeInfo(T);
    switch (info) {
        .Type => print("type \n\r", .{}),
        .Void => print("void \n\r", .{}),
        .Bool => print("bool \n\r", .{}),
        .NoReturn => print("noReturn\n\r", .{}),
        .Int => print("int \n\r", .{}),
        .Float => print("float\n\r", .{}),
        .Pointer => print("pointer \n\r", .{}),
        .Array => print("array \n\r", .{}),
        .Struct => {
            print("{s} = struct {{\n\r", .{@typeName(T)});
            if (info.Struct.fields.len > 0) {
                print("  fields {s}\n\r", .{ @TypeOf(info.Struct.fields) });
                inline for (info.Struct.fields) |field| {
                    print("    {s}: {s}\n\r", .{ field.name, @typeName(field.field_type) });
                }
            } 
            if (info.Struct.decls.len > 0) {
                inline for (info.Struct.decls) |decl| {
                    switch (decl.data) {
                        .Type => if (only_pub and decl.is_pub) print("  {s} {s}\n\r", .{ if (decl.is_pub) "pub" else "   ", decl.name }),
                        .Var => if (only_pub and decl.is_pub) print("  {s} {s}\n\r", .{ if (decl.is_pub) "pub" else "   ", decl.name }),
                        .Fn => if (only_pub and decl.is_pub) {
                            print("  {s} {s} {s}\n\r", .{ if (decl.is_pub) "pub" else "   ", decl.name , decl.data.Fn.fn_type });
                            if (decl.data.Fn.is_noinline) print("    noinline\n\r", .{});
                            if (decl.data.Fn.is_var_args) print("    var args\n\r", .{});
                            if (decl.data.Fn.is_extern) print("    extern\n\r", .{});
                            if (decl.data.Fn.is_export) print("    export\n\r", .{});
                            //print("    return_type: {s}\n\r", .{ decl.data.Fn.return_type });
                            if(decl.data.Fn.arg_names.len > 0) {
                                print("        arg_names(", .{});
                                inline for (decl.data.Fn.arg_names) |arg_name, index| {
                                    print("{s}{s}", .{ arg_name, if (index < decl.data.Fn.arg_names.len - 1) ", " else "" });
                                }
                                print(")\n\r", .{});
                            }
                        },
                    }
                }
            }
            if (info.Struct.is_tuple) print("  is_tuple\n\r", .{});
            if (!only_pub) print("  layout: {s}\n\r", .{ info.Struct.layout });
            print("}}\n\r", .{});
       },
        .ComptimeFloat => print("ComptimeFloat \n\r", .{}),
        .ComptimeInt => print("ComptimeInt \n\r", .{}),
        .Undefined => print("Undefined \n\r", .{}),
        .Null => print("Null \n\r", .{}),
        .Optional => print("Optional \n\r", .{}),
        .ErrorUnion => print("ErrorUnion \n\r", .{}),
        .ErrorSet => print("ErrorSet\n\r", .{}),
        .Enum => print("Enum \n\r", .{}),
        .Union => print("Union \n\r", .{}),
        .Fn => print("Fn \n\r", .{}),
        .BoundFn => print("BoundFn \n\r", .{}),
        .Opaque => print("Opaque \n\r", .{}),
        .Frame => print("Frame \n\r", .{}),
        .AnyFrame => print("AnyFrame\n\r", .{}),
        .Vector => print("Vector \n\r", .{}),
        .EnumLiteral => print("\n\r", .{}),
    }
}

test "reflect" {
    showType(std.build, true);
}