// a simple linked list that holds no data
// useful for allocators
pub const List = struct {
    next: ?*List = null,
};
