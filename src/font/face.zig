const std = @import("std");
const builtin = @import("builtin");
const options = @import("main.zig").options;
const Metrics = @import("main.zig").Metrics;
const config = @import("../config.zig");
const freetype = @import("face/freetype.zig");
const coretext = @import("face/coretext.zig");
pub const web_canvas = @import("face/web_canvas.zig");

/// Face implementation for the compile options.
pub const Face = switch (options.backend) {
    .freetype,
    .fontconfig_freetype,
    .coretext_freetype,
    => freetype.Face,

    .coretext,
    .coretext_harfbuzz,
    .coretext_noshape,
    => coretext.Face,

    .web_canvas => web_canvas.Face,
};

/// If a DPI can't be calculated, this DPI is used. This is probably
/// wrong on modern devices so it is highly recommended you get the DPI
/// using whatever platform method you can.
pub const default_dpi = if (builtin.os.tag == .macos) 72 else 96;

/// These are the flags to customize how freetype loads fonts. This is
/// only non-void if the freetype backend is enabled.
pub const FreetypeLoadFlags = if (options.backend.hasFreetype())
    config.FreetypeLoadFlags
else
    void;
pub const freetype_load_flags_default: FreetypeLoadFlags = if (FreetypeLoadFlags != void) .{} else {};

/// Options for initializing a font face.
pub const Options = struct {
    size: DesiredSize,
    freetype_load_flags: FreetypeLoadFlags = freetype_load_flags_default,
};

/// The desired size for loading a font.
pub const DesiredSize = struct {
    // Desired size in points
    points: f32,

    // The DPI of the screen so we can convert points to pixels.
    xdpi: u16 = default_dpi,
    ydpi: u16 = default_dpi,

    // Converts points to pixels
    pub fn pixels(self: DesiredSize) u16 {
        // 1 point = 1/72 inch
        return @intFromFloat(@round((self.points * @as(f32, @floatFromInt(self.ydpi))) / 72));
    }
};

/// A font variation setting. The best documentation for this I know of
/// is actually the CSS font-variation-settings property on MDN:
/// https://developer.mozilla.org/en-US/docs/Web/CSS/font-variation-settings
pub const Variation = struct {
    id: Id,
    value: f64,

    pub const Id = packed struct(u32) {
        d: u8,
        c: u8,
        b: u8,
        a: u8,

        pub fn init(v: *const [4]u8) Id {
            return .{ .a = v[0], .b = v[1], .c = v[2], .d = v[3] };
        }

        /// Converts the ID to a string. The return value is only valid
        /// for the lifetime of the self pointer.
        pub fn str(self: Id) [4]u8 {
            return .{ self.a, self.b, self.c, self.d };
        }
    };
};

/// Additional options for rendering glyphs.
pub const RenderOptions = struct {
    /// The metrics that are defining the grid layout. These are usually
    /// the metrics of the primary font face. The grid metrics are used
    /// by the font face to better layout the glyph in situations where
    /// the font is not exactly the same size as the grid.
    grid_metrics: Metrics,

    /// The number of grid cells this glyph will take up. This can be used
    /// optionally by the rasterizer to better layout the glyph.
    cell_width: ?u2 = null,

    /// Constraint and alignment properties for the glyph. The rasterizer
    /// should call the `constrain` function on this with the original size
    /// and bearings of the glyph to get remapped values that the glyph
    /// should be scaled/moved to.
    constraint: Constraint = .none,

    /// The number of cells, horizontally that the glyph is free to take up
    /// when resized and aligned by `constraint`. This is usually 1, but if
    /// there's whitespace to the right of the cell then it can be 2.
    constraint_width: u2 = 1,

    /// Thicken the glyph. This draws the glyph with a thicker stroke width.
    /// This is purely an aesthetic setting.
    ///
    /// This only works with CoreText currently.
    thicken: bool = false,

    /// "Strength" of the thickening, between `0` and `255`.
    /// Only has an effect when `thicken` is enabled.
    ///
    /// `0` does not correspond to *no* thickening,
    /// just the *lightest* thickening available.
    ///
    /// CoreText only.
    thicken_strength: u8 = 255,

    /// See the `constraint` field.
    pub const Constraint = struct {
        /// Don't constrain the glyph in any way.
        pub const none: Constraint = .{};

        /// Vertical sizing rule.
        size_vertical: Size = .none,
        /// Horizontal sizing rule.
        size_horizontal: Size = .none,

        /// Vertical alignment rule.
        align_vertical: Align = .none,
        /// Horizontal alignment rule.
        align_horizontal: Align = .none,

        /// Top padding when resizing.
        pad_top: f64 = 0.0,
        /// Left padding when resizing.
        pad_left: f64 = 0.0,
        /// Right padding when resizing.
        pad_right: f64 = 0.0,
        /// Bottom padding when resizing.
        pad_bottom: f64 = 0.0,

        // This acts as a multiple of the provided width when applying
        // constraints, so if this is 1.6 for example, then a width of
        // 10 would be treated as though it were 16.
        group_width: f64 = 1.0,
        // This acts as a multiple of the provided height when applying
        // constraints, so if this is 1.6 for example, then a height of
        // 10 would be treated as though it were 16.
        group_height: f64 = 1.0,
        // This is an x offset for the actual width within the group width.
        // If this is 0.5 then the glyph will be offset so that its left
        // edge sits at the halfway point of the group width.
        group_x: f64 = 0.0,
        // This is a y offset for the actual height within the group height.
        // If this is 0.5 then the glyph will be offset so that its bottom
        // edge sits at the halfway point of the group height.
        group_y: f64 = 0.0,

        /// Maximum ratio of width to height when resizing.
        max_xy_ratio: ?f64 = null,

        /// Maximum number of cells horizontally to use.
        max_constraint_width: u2 = 2,

        /// What to use as the height metric when constraining the glyph.
        constraint_type: ConstraintType = .cell,

        pub const Size = enum {
            /// Don't change the size of this glyph.
            none,
            /// Move the glyph and optionally scale it down
            /// proportionally to fit within the given axis.
            fit,
            /// Move and resize the glyph proportionally to
            /// cover the given axis.
            cover,
            /// Same as `cover` but not proportional.
            stretch,
        };

        pub const Align = enum {
            /// Don't move the glyph on this axis.
            none,
            /// Move the glyph so that its leading (bottom/left)
            /// edge aligns with the leading edge of the axis.
            start,
            /// Move the glyph so that its trailing (top/right)
            /// edge aligns with the trailing edge of the axis.
            end,
            /// Move the glyph so that it is centered on this axis.
            center,
        };

        pub const ConstraintType = enum {
            /// Use the full size of the cell for constraining this glyph.
            cell,
            /// Use icon constraints from the grid metrics
            icon,
        };

        /// Bounding box representing a size and position on the cell grid
        pub const BoundingBox = struct {
            width: f64,
            height: f64,
            x: f64,
            y: f64,
        };

        // Pad a bounding box as specified by the constraints
        fn pad_bbox(self: Constraint, bbox: BoundingBox) BoundingBox {
            return .{
                .width = (1 - (self.pad_left + self.pad_right)) * bbox.width,
                .height = (1 - (self.pad_bottom + self.pad_top)) * bbox.height,
                .x = bbox.x + (self.pad_left * bbox.width),
                .y = bbox.y + (self.pad_bottom * bbox.height),
            };
        }

        /// Apply this constraint to the provided glyph
        /// size, given the available width and height.
        pub fn constrain(
            self: Constraint,
            glyph: BoundingBox,
            metrics: Metrics,
            /// Number of cells horizontally available for this glyph.
            constraint_width: u2,
        ) BoundingBox {
            const full_width: f64 = @floatFromInt(metrics.cell_width * @min(self.max_constraint_width, constraint_width));
            const full_height: f64 = @floatFromInt(metrics.cell_height);

            // The maximal bounding box defined by the metrics and constraints
            const constraints: BoundingBox = switch (self.constraint_type) {
                .cell => self.pad_bbox(.{ .width = full_width, .height = full_height, .x = 0, .y = 0 }),
                .icon => bbox: {
                    // Icons may be subject to stricter constraints
                    const available_width = @min(full_width, @as(f64, @floatFromInt(metrics.icon_width)));
                    const available_height = @min(full_height, @as(f64, @floatFromInt(metrics.icon_height)));
                    break :bbox self.pad_bbox(.{
                        .width = available_width,
                        .height = available_height,
                        .x = (full_width - available_width) / 2,
                        .y = (full_height - available_height) / 2,
                    });
                },
            };

            const group_width = glyph.width * self.group_width;
            const group_height = glyph.height * self.group_height;

            // The bounding box for the glyph's scale group.
            // The point of the remainder of this function is to scale, stretch
            // and shift this bbox to fit within the constraints, and then use
            // the glyph's relative size and position within the group bbox to
            // obtain its absolute position and size of in cell coordinates.
            var group: BoundingBox = .{
                .width = group_width,
                .height = group_height,
                .x = glyph.x - (group_width * self.group_x),
                .y = glyph.y - (group_height * self.group_y),
            };

            switch (self.size_horizontal) {
                .none => {},
                .fit => if (group.width > constraints.width) {
                    const orig_height = group.height;
                    // Adjust our height and width to proportionally
                    // scale them to fit the glyph to the cell width.
                    group.height *= constraints.width / group.width;
                    group.width = constraints.width;
                    // Set our x to 0 since anything else would mean
                    // the glyph extends outside of the cell width.
                    group.x = 0;
                    // Compensate our y to keep things vertically
                    // centered as they're scaled down.
                    group.y += (orig_height - group.height) / 2;
                } else if ((group.width + group.x) > constraints.width) {
                    // If the width of the glyph can fit in the cell but
                    // is currently outside due to the left bearing, then
                    // we reduce the left bearing just enough to fit it
                    // back in the cell.
                    group.x = constraints.width - group.width;
                } else if (group.x < 0) {
                    group.x = 0;
                },
                .cover => {
                    const orig_height = group.height;

                    group.height *= constraints.width / group.width;
                    group.width = constraints.width;

                    group.x = 0;

                    group.y += (orig_height - group.height) / 2;
                },
                .stretch => {
                    group.width = constraints.width;
                    group.x = 0;
                },
            }

            switch (self.size_vertical) {
                .none => {},
                .fit => if (group.height > constraints.height) {
                    const orig_width = group.width;
                    // Adjust our height and width to proportionally
                    // scale them to fit the glyph to the cell height.
                    group.width *= constraints.height / group.height;
                    group.height = constraints.height;
                    // Set our y to 0 since anything else would mean
                    // the glyph extends outside of the cell height.
                    group.y = 0;
                    // Compensate our x to keep things horizontally
                    // centered as they're scaled down.
                    group.x += (orig_width - group.width) / 2;
                } else if ((group.height + group.y) > constraints.height) {
                    // If the height of the glyph can fit in the cell but
                    // is currently outside due to the bottom bearing, then
                    // we reduce the bottom bearing just enough to fit it
                    // back in the cell.
                    group.y = constraints.height - group.height;
                } else if (group.y < 0) {
                    group.y = 0;
                },
                .cover => {
                    const orig_width = group.width;

                    group.width *= constraints.height / group.height;
                    group.height = constraints.height;

                    group.y = 0;

                    group.x += (orig_width - group.width) / 2;
                },
                .stretch => {
                    group.height = constraints.height;
                    group.y = 0;
                },
            }

            // Reduce aspect ratio if required
            // We apply max_xy_ratio to the group rather than the individual
            // glyph, otherwise the scale group loses meaning. In any case, no
            // glyph that sets a max_xy_ratio is part of a scale group, so
            // there's no practical difference between applying max_xy_ratio
            // here or to the final glyph.
            if (self.max_xy_ratio) |ratio| if (group.width > (group.height * ratio)) {
                const orig_width = group.width;
                group.width = group.height * ratio;
                group.x += (orig_width - group.width) / 2;
            };

            // Apply prescribed alignment of the group within the constraints
            switch (self.align_horizontal) {
                .none => {},
                .start => group.x = 0,
                .end => group.x = constraints.width - group.width,
                .center => group.x = (constraints.width - group.width) / 2,
            }

            switch (self.align_vertical) {
                .none => {},
                .start => group.y = 0,
                .end => group.y = constraints.height - group.height,
                .center => group.y = (constraints.height - group.height) / 2,
            }

            // Shift origin of group bbox from constraints to cell
            group.x += constraints.x;
            group.y += constraints.y;

            // Use the glyph's relative position within the group bbox to
            // obtain the final glyph bbox in cell coordinates
            return .{
                .width = group.width / self.group_width,
                .height = group.height / self.group_height,
                .x = group.x + self.group_x * group.width,
                .y = group.y + self.group_y * group.height,
            };
        }
    };
};

test {
    @import("std").testing.refAllDecls(@This());
}

test "Variation.Id: wght should be 2003265652" {
    const testing = std.testing;
    const id = Variation.Id.init("wght");
    try testing.expectEqual(@as(u32, 2003265652), @as(u32, @bitCast(id)));
    try testing.expectEqualStrings("wght", &(id.str()));
}

test "Variation.Id: slnt should be 1936486004" {
    const testing = std.testing;
    const id: Variation.Id = .{ .a = 's', .b = 'l', .c = 'n', .d = 't' };
    try testing.expectEqual(@as(u32, 1936486004), @as(u32, @bitCast(id)));
    try testing.expectEqualStrings("slnt", &(id.str()));
}
