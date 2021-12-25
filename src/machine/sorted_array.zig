const std = @import("std");

/// An array which is sorted
pub fn SortedArray(comptime T: type, cmp: fn (lhs: T, rhs: T) bool) type {
    return struct {
        items: []T,

        /// Adapted compare function to pass to std.sort.sort
        fn compare(_: void, lhs: T, rhs: T) bool {
            return cmp(lhs, rhs);
        }

        /// Initialize the array set from
        /// a given slice. The slice gets
        /// sorted in place.
        pub fn init(items: []T) @This() {
            // Sort the items
            std.sort.sort(T, items, {}, compare);
            return .{
                .items = items,
            };
        }
    };
}
