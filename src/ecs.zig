//! Archetype Entity Component System

const std = @import("std");
const meta = std.meta;
const math = std.math;
const testing = std.testing;
const assert = std.debug.assert;
const todo = std.debug.todo;

const Allocator = std.mem.Allocator;

const is_debug = @import("builtin").mode == .Debug;

pub const Set = struct {
    data: DummyArrayList = .{},

    pub const DummyArrayList = struct {
        len: usize = 0,
    };

    const Self = @This();

    const vtable: Erased.VTable = .{
        .destroy = _destroy,
        .remove = _remove,
        .resize = _resize,
        .shrink = _shrink,
    };

    pub fn interface(self: *Self) Erased {
        return .{
            .base = @ptrCast(*Erased.Interface, self),
            .vtable = &vtable,
            .hash = if (is_debug) hash else {},
        };
    }

    pub const hash = std.hash.Wyhash.hash(0xdeadbeef, @typeName(Component(void)));

    pub fn create(gpa: Allocator) Allocator.Error!*Self {
        const self = try gpa.create(Self);
        self.* = .{};
        return self;
    }

    pub fn destroy(self: *Self, gpa: Allocator) void {
        gpa.destroy(self);
    }

    fn _resize(this: *Erased.Interface, gpa: Allocator, new_size: usize) Allocator.Error!void {
        _ = this;
        _ = gpa;
        _ = new_size;
    }

    fn _shrink(this: *Erased.Interface, new_size: usize) void {
        _ = this;
        _ = new_size;
    }

    fn _destroy(this: *Erased.Interface, gpa: Allocator) void {
        _ = this;
        _ = gpa;
    }

    fn _remove(this: *Erased.Interface, index: u32) u32 {
        _ = this;
        return index;
    }
};

pub fn Component(comptime T: type) type {
    switch (T) {
        void => return Set,
        else => {
            const List = std.MultiArrayList(T);
            return struct {
                data: List,

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
                    self.data.len += 1;
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
        },
    }
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
        if (is_debug and Component(T).hash != self.hash) {
            std.debug.panic("unexpected hash for {}", .{Component(T)});
        }
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
    alive: u32 = 0,
    dead: std.ArrayListUnmanaged(Entity) = .{},

    const log = std.log.scoped(.EntityManager);

    pub fn new(self: *EntityManager, gpa: Allocator) !Entity {
        if (self.dead.popOrNull()) |key| {
            return key;
        }

        try self.dead.ensureTotalCapacity(gpa, self.alive + 1);

        if (self.alive == math.maxInt(u32)) {
            return error.OutOfMemory;
        } else {
            defer self.alive += 1;
            return @intToEnum(Entity, self.alive);
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
        archetypes: std.AutoArrayHashMapUnmanaged(Signature, Archetype) = .{},
        command_queue: CommandQueue = .{},

        pub const CommandQueue = std.ArrayListUnmanaged(Command);

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

            /// Database
            model: *Self,
        };

        pub const Command = struct {
            command: Tag,
            signature: Signature,
            key: Entity,

            pub const Tag = enum(u8) {
                remove,
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

            pub fn init(tags: []const Tag) Signature {
                var signature: Signature = .empty;
                for (tags) |tag| signature.set(tag);
                return signature;
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

            pub fn disjoint(self: Signature, other: Signature) Signature {
                return @intToEnum(Signature, @enumToInt(self) & ~@enumToInt(other));
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
            values: anytype,
        ) !void {
            const Data = @TypeOf(values);
            const fields = meta.fields(Data);
            const entity = self.entities.getPtr(key) orelse return error.NotFound; // 404

            var new_signature = entity.signature;
            inline for (fields) |field| new_signature.set(@field(Signature.Tag, field.name));

            if (entity.signature != new_signature) {
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

                inline for (fields) |field| if (field.field_type != void) {
                    const tag = @field(Signature.Tag, field.name);
                    log.debug("{} adding new component .{}", .{ key, tag });
                    const D = meta.fieldInfo(T, tag).field_type;
                    const com = archetype.components[new_signature.indexOf(tag).?];
                    const component = com.cast(D);
                    const value = @field(values, field.name);

                    component.data.set(new_index, value);
                };
            } else {
                log.debug("{} updating components", .{key});
                inline for (fields) |field| if (field.field_type != void) {
                    const tag = @field(Signature.Tag, field.name);
                    const D = meta.fieldInfo(T, tag).field_type;
                    const archetype = self.archetypes.getPtr(entity.signature).?; // 404
                    const com = archetype.components[entity.signature.indexOf(tag).?];
                    const component = com.cast(D);
                    const value = @field(values, field.name);

                    component.data.set(entity.index, value);
                };
            }
        }

        pub fn remove(
            self: *Self,
            gpa: Allocator,
            key: Entity,
            tags: Signature,
        ) !void {
            const entity = self.entities.getPtr(key) orelse return error.NotFound; // 404
            const new_signature = entity.signature.disjoint(tags);

            if (new_signature != entity.signature) {
                const old_archetype = self.archetypes.getPtr(entity.signature).?; // 404

                const archetype = self.archetypes.getPtr(new_signature) orelse
                    try self.createArchetype(gpa, new_signature);

                const new_index = archetype.len;
                try archetype.reserve(gpa, key);

                log.debug("removing {} sub archetype {}", .{ key, tags });

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
                inline for (meta.fields(T)) |field, i| if (field.field_type != void) {
                    const tag = @intToEnum(Signature.Tag, i);
                    if (signature.has(tag) and old_signature.has(tag)) {
                        const old_component = old_archetype.components[old_signature.indexOf(tag).?];
                        const value = old_component.cast(field.field_type).data.get(index);
                        const com = archetype.components[signature.indexOf(tag).?];
                        const component = com.cast(field.field_type);
                        component.data.set(component.data.len - 1, value);
                    }
                };
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
            errdefer _ = self.archetypes.swapRemove(signature);

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

        pub fn step(
            self: *Self,
            gpa: Allocator,
            systems: anytype,
        ) !void {
            const info = @typeInfo(meta.Child(@TypeOf(systems))).Struct;

            var frame_allocator = std.heap.ArenaAllocator.init(gpa);
            defer frame_allocator.deinit();

            const arena = frame_allocator.allocator();

            var ret: anyerror!void = {};

            inline for (info.fields) |field| {
                const function = field.field_type.update;
                const system = &@field(systems, field.name);
                const System = meta.Child(@TypeOf(system));

                const Tuple = meta.ArgsTuple(@TypeOf(function));
                const shape = Signature.init(field.field_type.inputs);
                const inputs = field.field_type.inputs;
                const arguments = meta.fields(Tuple);

                if (@hasDecl(System, "begin")) {
                    try system.begin(.{
                        .gpa = gpa,
                        .arena = arena,
                    });
                }

                for (self.archetypes.keys()) |signature, index| {
                    if (signature.contains(shape)) {
                        const archetype = self.archetypes.values()[index];
                        if (archetype.len == 0) continue;

                        const components = archetype.components;

                        const context: Context = .{
                            .gpa = gpa,
                            .arena = arena,
                            .model = self,
                            .entities = archetype.entities.items,
                            .signature = signature,
                        };

                        var tuple: Tuple = undefined;
                        tuple.@"0" = system;

                        comptime var parameter: comptime_int = 1;
                        inline for (inputs) |tag| {
                            const Type = meta.fieldInfo(T, tag).field_type;
                            if (Type != void) {
                                const com = signature.indexOf(tag).?;
                                const component = components[com].cast(Type);
                                tuple[parameter] = component;
                                parameter += 1;
                            }
                        }

                        @field(tuple, arguments[arguments.len - 1].name) = context;
                        const options = .{ .modifier = .never_inline };
                        ret = @call(options, function, tuple);
                    }

                    try ret;
                }

                if (@hasDecl(System, "end")) {
                    try system.end(.{
                        .gpa = gpa,
                        .arena = arena,
                    });
                }

                try self.runCommands(gpa);
                self.command_queue.clearRetainingCapacity();
            }
        }

        fn runCommands(self: *Self, gpa: Allocator) !void {
            for (self.command_queue.items) |com| {
                switch (com.command) {
                    .remove => try self.remove(gpa, com.key, com.signature),
                    .delete => self.delete(com.key),
                }
            }
        }
    };
}
