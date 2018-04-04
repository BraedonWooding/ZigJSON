const Builder = @import("std").build.Builder;

pub fn build(b: &Builder) void {
    const mode = b.standardReleaseOptions();
    const test_step = b.step("test", "Run all the tests");
    const tests = b.addTest("tests/test.zig");
    tests.setBuildMode(mode);
    test_step.dependOn(&tests.step);
}
