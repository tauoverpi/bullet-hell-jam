//! Archetype Entity Component System

const std = @import("std");
const meta = std.meta;
const math = std.math;
const testing = std.testing;
const assert = std.debug.assert;
const todo = std.debug.todo;

const Allocator = std.mem.Allocator;

const is_debug = @import("builtin").mode == .Debug;

pub fn Component(comptime T: type) type {
    return struct {
        data: std.MultiArrayList(T),

        const vtable: Erased.VTable = .{
            .destroy = _destroy,
            .remove = _remove,
            .resize = _resize,
            .shrink = _shrink,
        };

        const Self = @This();

        pub fn interface(self: *Self) Erased {
            return .{
                .base = @ptrCast(*Erased.Interface, self),
                .vtable = &vtable,
                .hash = if (is_debug) hash else {},
            };
        }

        pub const hash = std.hash.Wyhash.hash(0xdeadbeef, @typeName(Component(T)));

        pub fn create(gpa: Allocator) Allocator.Error!*Self {
            const self = try gpa.create(Self);
            self.data = .{};
            return self;
        }

        pub fn destroy(self: *Self, gpa: Allocator) void {
            self.data.deinit(gpa);
            gpa.destroy(self);
        }

        fn _resize(this: *Erased.Interface, gpa: Allocator, new_size: usize) Allocator.Error!void {
            const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), this));
            try self.data.ensureTotalCapacity(gpa, new_size);
        }

        fn _shrink(this: *Erased.Interface, new_size: usize) void {
            const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), this));
            self.data.shrinkRetainingCapacity(new_size);
        }

        fn _destroy(this: *Erased.Interface, gpa: Allocator) void {
            const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), this));
            self.destroy(gpa);
        }

        fn _remove(this: *Erased.Interface, index: u32) u32 {
            const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), this));
            self.data.swapRemove(index);
            return index;
        }
    };
}

pub const Erased = struct {
    base: *Interface,
    vtable: *const VTable,
    hash: if (is_debug) u64 else void,

    pub const Interface = opaque {};

    pub const VTable = struct {
        destroy: fn (self: *Interface, gpa: Allocator) void,
        remove: fn (self: *Interface, index: u32) u32,
        shrink: fn (self: *Interface, new_size: usize) void,
        resize: fn (self: *Interface, gpa: Allocator, new_size: usize) Allocator.Error!void,
    };

    pub fn deinit(self: Erased, gpa: Allocator) void {
        self.vtable.destroy(self.base, gpa);
    }

    pub fn remove(self: Erased, index: u32) u32 {
        return self.vtable.remove(self.base, index);
    }

    pub fn resize(self: Erased, gpa: Allocator, new_size: usize) Allocator.Error!void {
        try self.vtable.resize(self.base, gpa, new_size);
    }

    pub fn shrink(self: Erased, new_size: usize) void {
        self.vtable.shrink(self.base, new_size);
    }

    pub fn cast(self: Erased, comptime T: type) *Component(T) {
        if (is_debug) assert(Component(T).hash == self.hash);
        return @ptrCast(*Component(T), @alignCast(@alignOf(*Component(T)), self.base));
    }
};

pub const Archetype = struct {
    len: u32 = 0,
    entities: std.ArrayListUnmanaged(Entity) = .{},
    components: []Erased = &.{},

    pub fn reserve(self: *Archetype, gpa: Allocator, key: Entity) Allocator.Error!void {
        var index: u16 = 0;

        try self.entities.append(gpa, key);
        errdefer self.entities.shrinkRetainingCapacity(self.entities.items.len - 1);

        errdefer for (self.components[0..index]) |erased| {
            erased.shrink(self.len);
        };

        for (self.components) |erased, i| {
            index = @intCast(u16, i);
            try erased.resize(gpa, self.len + 1);
        }

        self.len += 1;
    }

    pub fn deinit(self: *Archetype, gpa: Allocator) void {
        for (self.components) |erased| erased.deinit(gpa);
        gpa.free(self.components);
        assert(self.entities.items.len == 0);
        self.entities.deinit(gpa);
    }

    pub fn remove(self: *Archetype, index: u32) ?Entity {
        const removed = self.components[0].remove(index);
        const last = index + 1 == self.len;

        if (self.components.len > 1) {
            for (self.components[1..]) |erased| {
                assert(erased.remove(index) == removed);
            }
        }

        _ = self.entities.swapRemove(index);
        self.len -= 1;

        return if (last) null else self.entities.items[index];
    }
};

pub const Entity = enum(u32) { _ };

pub const EntityManager = struct {
    count: u32 = 0,
    dead: std.ArrayListUnmanaged(Entity) = .{},

    const log = std.log.scoped(.EntityManager);

    pub fn new(self: *EntityManager, gpa: Allocator) !Entity {
        if (self.dead.popOrNull()) |key| {
            return key;
        }

        try self.dead.ensureTotalCapacity(gpa, self.dead.items.len + 1);

        if (@addWithOverflow(u32, self.count, 1, &self.count)) {
            self.count = math.maxInt(u32);
            return error.OutOfMemory;
        } else {
            const key = @intToEnum(Entity, self.count - 1);
            return key;
        }
    }

    pub fn delete(self: *EntityManager, key: Entity) void {
        self.dead.appendAssumeCapacity(key);
    }

    pub fn deinit(self: *EntityManager, gpa: Allocator) void {
        assert(self.dead.items.len == self.count);
        self.dead.deinit(gpa);
    }
};

pub fn Model(comptime T: type) type {
    return struct {
        manager: EntityManager = .{},
        entities: std.AutoHashMapUnmanaged(Entity, Pointer) = .{},
        archetypes: std.AutoHashMapUnmanaged(Signature, Archetype) = .{},
        command_queue: CommandQueue = .{},

        pub const CommandQueue = std.ArrayListUnmanaged(Command);
        pub const CommandQueueManaged = std.ArrayList(Command);

        const log = std.log.scoped(.Model);

        pub const Context = struct {
            /// General purpose allocator
            gpa: Allocator,

            /// Allocator for scratch memory which survives to the end of the frame
            arena: Allocator,

            /// Slice of entities belonging to the current archetype
            entities: []const Entity,

            /// Signature of the archetype
            signature: Signature,

            /// Queue of commands to be run after the system updates
            command_queue: *CommandQueueManaged,
        };

        pub const Command = struct {
            command: Tag,
            key: Entity,
            tag: Signature.Tag,

            pub const Tag = enum(u8) {
                remove,
                add,
                delete,
            };
        };

        pub const Signature = enum(Int) {
            empty,
            _,

            pub const Tag = meta.FieldEnum(T);
            pub const Int = meta.Int(.unsigned, len);
            pub const len = meta.fields(T).len;

            pub fn format(value: Signature, comptime _: []const u8, options: anytype, writer: anytype) !void {
                _ = options;

                const str = comptime std.fmt.comptimePrint("[{{b:0>{d}}}]", .{len});

                try writer.print(str, .{@enumToInt(value)});
            }

            pub fn set(self: *Signature, tag: Tag) void {
                const bit = @as(Int, 1) << @enumToInt(tag);
                self.* = @intToEnum(Signature, @enumToInt(self.*) | bit);
            }

            pub fn with(self: Signature, tag: Tag) Signature {
                var copy = self;
                copy.set(tag);
                return copy;
            }

            pub fn unset(self: *Signature, tag: Tag) void {
                const mask = ~(@as(Int, 1) << @enumToInt(tag));
                self.* = @intToEnum(Signature, @enumToInt(self.*) & mask);
            }

            pub fn without(self: Signature, tag: Tag) Signature {
                var copy = self;
                copy.unset(tag);
                return copy;
            }

            pub fn has(self: Signature, tag: Tag) bool {
                const bit = @as(Int, 1) << @enumToInt(tag);
                return @enumToInt(self) & bit != 0;
            }

            pub fn count(self: Signature) u16 {
                return @popCount(Int, @enumToInt(self));
            }

            pub fn indexOf(self: Signature, tag: Tag) ?u16 {
                if (!self.has(tag)) return null;

                const max: Int = math.maxInt(Int);
                const mask = ~(max << @enumToInt(tag));

                return @popCount(Int, @enumToInt(self) & mask);
            }

            pub fn intersection(self: Signature, other: Signature) Signature {
                return @intToEnum(Signature, @enumToInt(self) & @enumToInt(other));
            }

            pub fn contains(self: Signature, other: Signature) bool {
                return self.intersection(other).count() == other.count();
            }
        };

        pub const Pointer = struct {
            index: u32,
            signature: Signature,
        };

        const Self = @This();

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.manager.deinit(gpa);
            self.entities.deinit(gpa);

            var it = self.archetypes.valueIterator();
            while (it.next()) |archetype| archetype.deinit(gpa);

            self.archetypes.deinit(gpa);
            self.command_queue.deinit(gpa);
        }

        pub fn new(self: *Self, gpa: Allocator) Allocator.Error!Entity {
            const key = try self.manager.new(gpa);
            errdefer self.manager.delete(key);

            log.debug("created new entity {}", .{key});

            try self.entities.putNoClobber(gpa, key, .{
                .index = math.maxInt(u32),
                .signature = .empty,
            });

            return key;
        }

        pub fn delete(self: *Self, key: Entity) void {
            self.manager.delete(key);

            log.debug("deleted entity {}", .{key});

            const entity = self.entities.fetchRemove(key).?.value;

            if (entity.signature != .empty) {
                const old_archetype = self.archetypes.getPtr(entity.signature).?;

                self.migrateArchetype(
                    entity.index,
                    undefined,
                    .empty,
                    old_archetype,
                    entity.signature,
                );
            }
        }

        pub fn get(
            self: *Self,
            key: Entity,
            comptime tag: Signature.Tag,
        ) ?meta.fieldInfo(T, tag).field_type {
            const D = meta.fieldInfo(T, tag).field_type;
            const entity = self.entities.get(key).?;

            if (!entity.signature.has(tag)) return null;

            const archetype = self.archetypes.getPtr(entity.signature).?;
            const component = archetype.components[entity.signature.indexOf(tag).?];

            return component.cast(D).data.get(entity.index);
        }

        pub fn update(
            self: *Self,
            gpa: Allocator,
            key: Entity,
            comptime tag: Signature.Tag,
            value: meta.fieldInfo(T, tag).field_type,
        ) !void {
            const D = @TypeOf(value);
            const entity = self.entities.getPtr(key) orelse return error.NotFound; // 404
            const new_signature = entity.signature.with(tag);

            if (entity.signature != new_signature) {
                log.debug("adding {} component .{s} index {d}", .{ key, @tagName(tag), entity.index });
                const archetype = self.archetypes.getPtr(new_signature) orelse
                    try self.createArchetype(gpa, new_signature);
                const new_index = archetype.len;

                try archetype.reserve(gpa, key);
                errdefer archetype.shrink(new_index);

                if (entity.signature != .empty) {
                    const old_archetype = self.archetypes.getPtr(entity.signature).?; // 404

                    self.migrateArchetype(
                        entity.index,
                        archetype,
                        new_signature,
                        old_archetype,
                        entity.signature,
                    );
                }

                entity.index = new_index;
                entity.signature = new_signature;
                log.debug("{d} moved to {} index {}", .{ key, entity.signature, entity.index });

                const com = archetype.components[new_signature.indexOf(tag).?];
                const component = com.cast(D);
                component.data.appendAssumeCapacity(value);
            } else {
                log.debug("updating {} in {} component .{s} index {d}", .{ key, entity.signature, @tagName(tag), entity.index });
                const archetype = self.archetypes.getPtr(entity.signature).?; // 404
                const com = archetype.components[entity.signature.indexOf(tag).?];

                com.cast(D).data.set(entity.index, value);
            }
        }

        pub fn remove(
            self: *Self,
            gpa: Allocator,
            key: Entity,
            tag: Signature.Tag,
        ) !void {
            const entity = self.entities.getPtr(key) orelse return error.NotFound; // 404
            const new_signature = entity.signature.without(tag);

            if (new_signature != entity.signature) {
                const old_archetype = self.archetypes.getPtr(entity.signature).?; // 404

                const archetype = self.archetypes.getPtr(new_signature) orelse
                    try self.createArchetype(gpa, new_signature);

                const new_index = archetype.len;
                try archetype.reserve(gpa, key);

                log.debug("removing {} component .{s}", .{ key, @tagName(tag) });

                self.migrateArchetype(
                    entity.index,
                    archetype,
                    new_signature,
                    old_archetype,
                    entity.signature,
                );

                entity.index = new_index;
                entity.signature = new_signature;

                log.debug("{} of {} index {d}", .{ key, entity.signature, entity.index });
            }
        }

        fn migrateArchetype(
            self: *Self,
            index: u32,
            archetype: *Archetype,
            signature: Signature,
            old_archetype: *Archetype,
            old_signature: Signature,
        ) void {
            log.debug("migrating {} from {} to {} index {d}", .{
                old_archetype.entities.items[index],
                old_signature,
                signature,
                index,
            });

            if (signature != .empty) {
                inline for (meta.fields(T)) |field, i| {
                    const tag = @intToEnum(Signature.Tag, i);
                    if (signature.has(tag) and old_signature.has(tag)) {
                        const old_component = old_archetype.components[old_signature.indexOf(tag).?];
                        const value = old_component.cast(field.field_type).data.get(index);
                        const component = archetype.components[signature.indexOf(tag).?];

                        component.cast(field.field_type).data.appendAssumeCapacity(value);
                    }
                }
            }

            const key = old_archetype.entities.items[index];
            log.debug("removing {} from old archetype {} index {d}", .{
                key,
                old_signature,
                index,
            });

            if (old_archetype.remove(index)) |moved_key| {
                const moved = self.entities.getPtr(moved_key).?; // 404
                log.debug("moving {} within {} from index {d} to index {d}", .{
                    moved_key,
                    moved.signature,
                    moved.index,
                    index,
                });
                moved.index = index;
            }
        }

        fn createArchetype(self: *Self, gpa: Allocator, signature: Signature) Allocator.Error!*Archetype {
            log.debug("creating new archetype {}", .{signature});
            const entry = try self.archetypes.getOrPut(gpa, signature);
            errdefer _ = self.archetypes.remove(signature);

            assert(!entry.found_existing);

            const archetype = entry.value_ptr;

            archetype.* = .{};

            archetype.components = try gpa.alloc(Erased, signature.count());
            errdefer gpa.free(archetype.components);

            var position: u16 = 0;
            inline for (meta.fields(T)) |field, index| {
                const tag = @intToEnum(Signature.Tag, index);
                if (signature.has(tag)) {
                    const com = try Component(field.field_type).create(gpa);
                    archetype.components[position] = com.interface();
                    position += 1;
                }
            }

            return archetype;
        }
    };
}

pub fn EntityComponentSystem(comptime T: type) type {
    return struct {
        model: Store = .{},
        systems: Update = .{},
        count: u64 = 0,

        pub const Store = Model(T);

        const log = std.log.scoped(.EntityComponentSystem);

        pub const Update = blk: {
            comptime var systems: []const type = &.{};
            for (meta.declarations(T)) |decl| {
                if (decl.is_pub and @hasDecl(@field(T, decl.name), "phase")) {
                    systems = systems ++ [_]type{@field(T, decl.name)};
                }
            }

            var phased: [systems.len]type = systems[0..systems.len].*;

            std.sort.sort(type, &phased, {}, struct {
                pub fn lessThan(_: void, comptime l: type, comptime r: type) bool {
                    return l.phase < r.phase;
                }
            }.lessThan);

            var fields: [systems.len]std.builtin.TypeInfo.StructField = undefined;

            for (fields) |*field, index| {
                const system = phased[index];
                const default = if (@bitSizeOf(system) == 0) "" else &system{};
                field.* = .{
                    .field_type = system,
                    .name = @typeName(system),
                    .alignment = 0,
                    .is_comptime = false,
                    .default_value = default,
                };
            }

            break :blk @Type(.{ .Struct = .{
                .layout = .Auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };

        const Self = @This();

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.model.deinit(gpa);
            inline for (meta.fields(Update)) |field| {
                if (@hasDecl(field.field_type, "deinit")) {
                    @field(self.systems, field.name).deinit(gpa);
                }
            }
        }

        fn call(f: anytype, x: anytype) !void {
            try @call(.{}, f, x);
        }

        /// Update one frame of the simulation
        pub fn update(self: *Self, gpa: Allocator) !void {
            var frame_allocator = std.heap.ArenaAllocator.init(gpa);
            defer frame_allocator.deinit();

            const arena = frame_allocator.allocator();

            defer self.count +%= 1;
            log.debug("frame {d} start", .{self.count});
            defer log.debug("frame {d} end", .{self.count});
            inline for (meta.fields(Update)) |field| {
                var it = self.model.archetypes.iterator();
                const system = field.field_type;
                const A = meta.ArgsTuple(@TypeOf(system.update));

                // fill the interface arguments
                var arguments: A = undefined;
                arguments.@"0" = &@field(self.systems, field.name);
                arguments.@"1" = .{
                    .gpa = gpa,
                    .arena = arena,
                    // set for each component
                    .command_queue = undefined,
                    .signature = undefined,
                    .entities = undefined,
                };

                while (it.next()) |entry| {
                    var shape: Store.Signature = .empty;
                    for (system.dependencies) |tag| shape.set(tag);
                    if (entry.key_ptr.contains(shape)) {
                        const archetype = entry.value_ptr;

                        arguments.@"1".signature = entry.key_ptr.*;
                        arguments.@"1".entities = entry.value_ptr.entities.items;
                        arguments.@"1".command_queue = &self.model.command_queue.toManaged(gpa);

                        // recover the command queue
                        defer self.model.command_queue =
                            arguments.@"1"
                            .command_queue
                            .moveToUnmanaged();

                        if (archetype.len != 0) {
                            log.debug("{s}: updating {} ({d})", .{
                                field.name,
                                entry.key_ptr.*,
                                archetype.len,
                            });

                            const components = archetype.components;

                            inline for (meta.fields(A)[2..]) |sub, index| {
                                const name = sub.name;
                                const tag = system.dependencies[index];
                                const offset = entry.key_ptr.indexOf(tag).?;
                                const D = meta.fieldInfo(T, tag).field_type;
                                @field(arguments, name) = components[offset].cast(D);
                            }

                            try call(system.update, arguments);
                        }
                    }
                }

                try self.runCommandQueue(gpa);
                self.model.command_queue.shrinkRetainingCapacity(0);
            }
        }

        fn runCommandQueue(self: *Self, gpa: Allocator) !void {
            for (self.model.command_queue.items) |com| {
                log.debug("{} command .{s} tag {}", .{ com.key, @tagName(com.command), com.tag });
                switch (com.command) {
                    .add => todo("handle the value init somehow"),
                    .remove => try self.model.remove(gpa, com.key, com.tag),
                    .delete => self.model.delete(com.key),
                }
            }
        }
    };
}

test {
    const Position = struct { x: u32, y: u32 };
    const Velocity = struct { x: u32, y: u32 };

    const DB = Model(struct {
        position: Position,
        velocity: Velocity,
        hp: struct { hp: u32 },
        mp: struct { mp: u32 },
    });

    const gpa = testing.allocator;

    var db: DB = .{};
    defer db.deinit(gpa);

    const car = try db.new(gpa);
    defer db.delete(car);

    {
        try db.update(gpa, car, .position, .{ .x = 5, .y = 5 });

        const ptr = db.entities.get(car).?;
        const archetype = db.archetypes.getPtr(ptr.signature).?;
        const position = archetype.components[ptr.signature.indexOf(.position).?].cast(Position);

        try testing.expectEqual(@as(u32, 5), position.data.items(.x)[ptr.index]);
    }

    {
        try db.update(gpa, car, .velocity, .{ .x = 1, .y = 1 });

        const ptr = db.entities.get(car).?;
        const archetype = db.archetypes.getPtr(ptr.signature).?;
        const position = archetype.components[ptr.signature.indexOf(.position).?].cast(Position);
        const velocity = archetype.components[ptr.signature.indexOf(.velocity).?].cast(Velocity);

        try testing.expectEqual(@as(u32, 5), position.data.items(.x)[ptr.index]);
        try testing.expectEqual(@as(u32, 1), velocity.data.items(.x)[ptr.index]);
    }
    {
        try db.update(gpa, car, .velocity, .{ .x = 1, .y = 1 });

        const ptr = db.entities.get(car).?;
        const archetype = db.archetypes.getPtr(ptr.signature).?;
        const velocity = archetype.components[ptr.signature.indexOf(.velocity).?].cast(Velocity);

        try testing.expectEqual(@as(u32, 1), velocity.data.items(.x)[ptr.index]);
    }

    var objects: u32 = 0;

    var it = db.archetypes.valueIterator();
    while (it.next()) |archetype| {
        objects += archetype.len;
    }

    try testing.expectEqual(@as(u32, 1), objects);
}

test {
    const Specification = struct {
        position: Position,
        velocity: Velocity,

        pub const Position = struct { x: u32, y: u32 };
        pub const Velocity = struct { x: u32, y: u32 };

        const Data = @This();

        pub const Movement = struct {
            const DB = Model(Data);
            pub const phase = 0;
            pub const dependencies: []const DB.Signature.Tag = &.{
                .position, .velocity,
            };

            const log = std.log.scoped(.Movement);

            pub fn update(
                self: *Movement,
                context: DB.Context,
                position: *Component(Position),
                velocity: *const Component(Velocity),
            ) !void {
                _ = self;
                _ = context;

                var index: u32 = 0;

                while (index < position.data.len) : (index += 1) {
                    const px = &position.data.items(.x)[index];
                    const py = &position.data.items(.y)[index];
                    const v = velocity.data.get(index);

                    log.debug(".{{ .x = {d} + {d}, .y = {d} + {d} }}", .{
                        px.*,
                        v.x,
                        py.*,
                        v.y,
                    });

                    px.* += v.x;
                    py.* += v.y;
                }
            }
        };
    };

    const Game = EntityComponentSystem(Specification);

    const gpa = testing.allocator;

    var game: Game = .{};
    defer game.deinit(gpa);

    const person = try game.model.new(gpa);
    defer game.model.delete(person);

    try game.model.update(gpa, person, .position, .{ .x = 42, .y = 69 });
    try game.model.update(gpa, person, .velocity, .{ .x = 1, .y = 1 });

    try game.update(gpa);
    try game.update(gpa);
    try game.update(gpa);

    try game.model.remove(gpa, person, .position);

    try game.update(gpa);
    try game.update(gpa);

    try game.model.update(gpa, person, .position, .{ .x = 42, .y = 69 });

    try game.update(gpa);
    try game.update(gpa);
    try game.update(gpa);

    var objects: u32 = 0;

    var it = game.model.archetypes.valueIterator();
    while (it.next()) |archetype| {
        objects += archetype.len;
    }
}
