var singleton: ?Freelist = null;
const Freelist = struct {};

pub fn alloc() void {
    if (singleton == null) singleton = Freelist{};
    const freelist = singleton;

    _ = freelist;
}
