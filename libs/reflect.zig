const std = @import("std");
const print = std.debug.print;

pub fn showType(comptime T: type, only_pub: bool) void {
    const info = @typeInfo(T);
    switch (info) {
        .Type => print("type \n", .{}),
        .Void => print("void \n", .{}),
        .Bool => print("bool \n", .{}),
        .NoReturn => print("noReturn\n", .{}),
        .Int => print("int \n", .{}),
        .Float => print("float\n", .{}),
        .Pointer => print("pointer \n", .{}),
        .Array => print("array \n", .{}),
        .Struct => {
            print("{s} = struct {{\n", .{@typeName(T)});
            if (info.Struct.fields.len > 0) {
                print("  fields {s}\n", .{ @TypeOf(info.Struct.fields) });
                inline for (info.Struct.fields) |field| {
                    print("    {s}: {s}\n", .{ field.name, @typeName(field.field_type) });
                }
            } 
            if (info.Struct.decls.len > 0) {
                inline for (info.Struct.decls) |decl| {
                    switch (decl.data) {
                        .Type => if (only_pub and decl.is_pub) print("  {s} {s}\n", .{ if (decl.is_pub) "pub" else "   ", decl.name }),
                        .Var => if (only_pub and decl.is_pub) print("  {s} {s}\n", .{ if (decl.is_pub) "pub" else "   ", decl.name }),
                        .Fn => if (only_pub and decl.is_pub) {
                            print("  {s} {s} {s}\n", .{ if (decl.is_pub) "pub" else "   ", decl.name , decl.data.Fn.fn_type });
                            if (decl.data.Fn.is_noinline) print("    noinline\n", .{});
                            if (decl.data.Fn.is_var_args) print("    var args\n", .{});
                            if (decl.data.Fn.is_extern) print("    extern\n", .{});
                            if (decl.data.Fn.is_export) print("    export\n", .{});
                            //print("    return_type: {s}\n", .{ decl.data.Fn.return_type });
                            if(decl.data.Fn.arg_names.len > 0) {
                                inline for (decl.data.Fn.arg_names) |arg_name| {
                                    print("    arg_name: {s}\n", .{ arg_name });
                                }
                            }
                        },
                    }
                }
            }
            if (info.Struct.is_tuple) print("  is_tuple\n", .{});
            if (!only_pub) print("  layout: {s}\n", .{ info.Struct.layout });
            print("}}\n", .{});
       },
        .ComptimeFloat => print("ComptimeFloat \n", .{}),
        .ComptimeInt => print("ComptimeInt \n", .{}),
        .Undefined => print("Undefined \n", .{}),
        .Null => print("Null \n", .{}),
        .Optional => print("Optional \n", .{}),
        .ErrorUnion => print("ErrorUnion \n", .{}),
        .ErrorSet => print("ErrorSet\n", .{}),
        .Enum => print("Enum \n", .{}),
        .Union => print("Union \n", .{}),
        .Fn => print("Fn \n", .{}),
        .BoundFn => print("BoundFn \n", .{}),
        .Opaque => print("Opaque \n", .{}),
        .Frame => print("Frame \n", .{}),
        .AnyFrame => print("AnyFrame\n", .{}),
        .Vector => print("Vector \n", .{}),
        .EnumLiteral => print("\n", .{}),
    }
}