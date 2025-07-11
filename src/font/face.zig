const std = @import("std");
const builtin = @import("builtin");
const build_config = @import("../build_config.zig");
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
    pub fn pixels(self: DesiredSize) f32 {
        // 1 point = 1/72 inch
        return (self.points * @as(f32, @floatFromInt(self.ydpi))) / 72;
    }

    /// Make this a valid gobject if we're in a GTK environment.
    pub const getGObjectType = switch (build_config.app_runtime) {
        .gtk, .@"gtk-ng" => @import("gobject").ext.defineBoxed(
            DesiredSize,
            .{ .name = "GhosttyFontDesiredSize" },
        ),

        .none => void,
    };
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

        /// Sizing rule.
        size: Size = .none,

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

        // Relative size and position of the glyph within the bounding box of its scale group.
        width_in_group: f64 = 1.0,
        height_in_group: f64 = 1.0,
        x_in_group: f64 = 0.0,
        y_in_group: f64 = 0.0,

        /// Maximum aspect ratio (width/height) to allow when stretching.
        max_xy_ratio: ?f64 = null,

        /// Maximum number of cells horizontally to use.
        max_constraint_width: u2 = 2,

        /// Whether to resize with respect to the icon height instead of the line height.
        /// Only applies when the constraint width is 1.
        use_icon_height: bool = false,

        /// Whether to apply horizontal alignment to the scale group or the glyph itself.
        align_horizontal_by_group: bool = false,

        pub const Size = enum {
            /// Don't change the size of this glyph.
            none,
            /// Downscale the glyph if needed to fit within the bounds,
            /// preserving aspect ratio. If the constraint width is 1,
            /// also scale up like fit
            limit,
            /// Scale the glyph up or down to exactly fit the bounds,
            /// preserving aspect ratio.
            fit,
            /// Stretch the glyph to exactly fit the bounds.
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
            /// Move the glyph so that it is centered in its
            /// constraint width
            center,
            /// Move the glyph so that it is centered in the first
            /// cell of its constraint width
            center_first,
        };

        /// Bounding box representing a size and position on the cell grid
        pub const Glyph = struct {
            width: f64,
            height: f64,
            x: f64,
            y: f64,
        };

        fn scale_factors(
            self: Constraint,
            group: Glyph,
            metrics: Metrics,
            min_constraint_width: u2,
        ) struct { f64, f64 } {
            if (self.size == .none) {
                return .{ 1.0, 1.0 };
            }

            const is_single_width = (min_constraint_width < 2);
            const pad_width_factor = @as(f64, @floatFromInt(min_constraint_width)) - (self.pad_left + self.pad_right);
            const pad_height_factor = 1 - (self.pad_bottom + self.pad_top);
            const target_width = pad_width_factor * metrics.face_width;
            const target_height = pad_height_factor * if (is_single_width and self.use_icon_height)
                metrics.icon_height
            else
                metrics.face_height;

            var width_factor = target_width / group.width;
            var height_factor = target_height / group.height;

            switch (self.size) {
                .none => unreachable,
                .limit => {
                    // Scale down to fit if needed
                    width_factor = @min(width_factor, height_factor);
                    if (!is_single_width) {
                        // For double-width constraints, we only scale down.
                        // font_patcher also considers whether there's overlap (negative
                        // padding) here, but our preprocessing would set self.size to
                        // .fit if that were the case.
                        width_factor = @min(1.0, width_factor);
                    }
                    height_factor = width_factor;
                },
                .fit => {
                    // Scale up or down to fit
                    width_factor = @min(width_factor, height_factor);
                    height_factor = width_factor;
                },
                .stretch => {},
            }

            // Reduce aspect ratio if required
            if (self.max_xy_ratio) |ratio| {
                if (group.width * width_factor > group.height * height_factor * ratio) {
                    width_factor = group.height * height_factor * ratio / group.width;
                }
            }

            return .{ width_factor, height_factor };
        }

        /// Apply this constraint to the provided glyph
        /// size, given the available width and height.
        pub fn constrain(
            self: Constraint,
            glyph: Glyph,
            metrics: Metrics,
            /// Number of cells horizontally available for this glyph.
            constraint_width: u2,
        ) Glyph {
            if ((self.size == .none) and (self.align_vertical == .none) and (self.align_horizontal == .none)) {
                return glyph;
            }

            // The bounding box for the glyph's scale group.
            // Scaling and alignment rules are calculated for this box and
            // then then applied to the glyph.
            var group: Glyph = group: {
                const group_width = glyph.width / self.width_in_group;
                const group_height = glyph.height / self.height_in_group;
                break :group .{
                    .width = group_width,
                    .height = group_height,
                    .x = glyph.x - (group_width * self.x_in_group),
                    .y = glyph.y - (group_height * self.y_in_group),
                };
            };

            const min_constraint_width: u2 = min_constraint_width: {
                // For extra wide font faces, never stretch glyphs across two cells
                if ((self.size == .stretch) and (metrics.face_width > 0.9 * metrics.face_height)) {
                    break :min_constraint_width 1;
                }
                break :min_constraint_width @min(self.max_constraint_width, constraint_width);
            };

            // The constrained glyph bounding box
            var constrained_glyph = glyph;

            // Apply prescribed scaling
            const width_factor, const height_factor = self.scale_factors(group, metrics, min_constraint_width);
            if ((width_factor != 1) or (height_factor != 1)) {
                constrained_glyph.width *= width_factor;
                constrained_glyph.height *= height_factor;
                constrained_glyph.x *= width_factor;
                // constrained_glyph.y *= height_factor;

                // NOTE: Here, font_patcher adds a slight extra padding to the
                // width, rounds to integer in font definition units, and, if
                // constraints are single-width, triple checks that the width is
                // within the constraints, adjusting as necessary. This is
                // relevant when statically patching a font file, where metrics
                // are saved in integer-valued font definition units, but not
                // when doing floating-point valued pixel unit calculations for
                // rendering, so we don't bother with any of that here.

                // Scale the group bounding box to prepare for alignment calculations
                group.width *= width_factor;
                group.height *= height_factor;
                group.x *= width_factor;
                // group.y *= height_factor;
                // NOTE: This deviates from font_patcher by centering vertical
                // scaling on the baseline rather than the lower left corner. In
                // practice, it doesn't make any difference, as every single NF
                // icon specifies centered vertical alignment.
                const baseline: f64 = @floatFromInt(metrics.cell_baseline);
                group.y = baseline + (height_factor * (group.y - baseline));
                constrained_glyph.y = group.y + (self.y_in_group * group.height);
            }
            if (!self.align_horizontal_by_group) {
                group.width = constrained_glyph.width;
                group.x = constrained_glyph.x;
            }

            // Align
            if (self.align_vertical != .none) {
                // We want to center in the line as defined by the face, which may be
                // different from the cell height if adjust-cell-height has been used.
                // The extra padding is always rounded to an integer number of pixels,
                // with the extra pixel added on top if the number is odd.
                const cell_height: f64 = @floatFromInt(metrics.cell_height);
                const line_height = @ceil(metrics.face_height);
                const adjust_bottom = @floor((cell_height - line_height) / 2);
                const pad_bottom = self.pad_bottom * metrics.face_height;
                const pad_top = line_height - (self.pad_top * metrics.face_height);
                const new_group_y = adjust_bottom + switch (self.align_vertical) {
                    .none => unreachable,
                    .center, .center_first => (line_height - group.height) / 2,
                    // .start and .end are currently not used by any glyph for vertical alignment
                    .start => pad_bottom,
                    .end => pad_top - group.height,
                };
                constrained_glyph.y += new_group_y - group.y;
            }

            if (self.align_horizontal != .none) {
                // Since we have the benefit of aligning with knowledge of the cell
                // width adjustment, we improve on font_patcher here by aligning
                // within the span from the left edge of the first unadjusted cell
                // to the right edge of the last unadjusted cell, as they sit within
                // the adjusted cell.
                //
                // If the adjusted cell is wider, the unadjusted cell is centered but
                // rounded left to the nearest whole pixel. If it's narrower, the left
                // edge of the unadjusted cell is flush with the adjusted cell.
                const single_cell_width: f64 = @floatFromInt(metrics.cell_width);
                const single_width = @ceil(metrics.face_width);
                const diff = single_cell_width - single_width;
                const adjust_left = @max(0, @floor(diff / 2));
                const full_cell_width: f64 = @floatFromInt(min_constraint_width * metrics.cell_width);
                const full_width: f64 = full_cell_width - diff;
                const pad_left = self.pad_left * metrics.face_width;
                const pad_right = full_width - self.pad_right * metrics.face_width;
                const new_group_x = adjust_left + switch (self.align_horizontal) {
                    .none => unreachable,
                    .start => pad_left,
                    // even with .center* and .end, there's a hard stop at pad_left
                    .center => @max(pad_left, (full_width - group.width) / 2),
                    .center_first => @max(pad_left, (single_width - group.width) / 2),
                    .end => @max(pad_left, pad_right - group.width),
                };
                constrained_glyph.x += new_group_x - group.x;
            }

            return constrained_glyph;
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
