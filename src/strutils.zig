pub fn streql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |char, i| {
        if (char != b[i]) return false;
    }
    return true;
}

pub fn trim(str: []const u8) []const u8 {
    var trim_start: usize = 0;
    var end: usize = str.len;

    // Trim from start
    while (trim_start < str.len and (str[trim_start] == ' ' or str[trim_start] == '\n' or str[trim_start] == '\r')) {
        trim_start += 1;
    }

    // Trim from end
    while (end > trim_start and (str[end - 1] == ' ' or str[end - 1] == '\n' or str[end - 1] == '\r')) {
        end -= 1;
    }

    return str[trim_start..end];
}
