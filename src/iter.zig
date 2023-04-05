const std = @import("std");

pub fn iterateLines(s: []const u8) LineIterator {
    return .{
        .index = 0,
        .s = s,
    };
}

const LineIterator = struct {
    s: []const u8,
    index: usize,

    pub fn next(self: *LineIterator) ?[]const u8 {
        const start = self.index;

        if (start >= self.s.len) {
            return null;
        }

        self.index += 1;
        while (self.index < self.s.len and self.s[self.index] != '\n') {
            self.index += 1;
        }

        const end = self.index;
        if (start == 0) {
            return self.s[start..end];
        } else {
            return self.s[start + 1 .. end];
        }
    }
};

test "iter" {
  var it = iterateLines("1\n23");
  const r1 = it.next().?;
  var it2 = iterateLines("123");
  const r2 = it2.next().?;

  try std.testing.expect(std.mem.eql(u8, r1, "1"));
  try std.testing.expect(std.mem.eql(u8, r2, "123"));
}
