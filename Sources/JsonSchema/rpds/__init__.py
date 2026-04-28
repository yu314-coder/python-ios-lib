"""rpds stub for iOS — immutable persistent data structures.

Real rpds uses Rust-backed persistent structures. This stub wraps Python
builtins but preserves the IMMUTABLE API: mutating methods return NEW
instances instead of modifying in place. Critical for jsonschema/referencing.
"""


class HashTrieMap(dict):
    """Immutable dict — update/insert/remove return new instances."""

    @classmethod
    def convert(cls, mapping):
        if mapping is None:
            return cls()
        if isinstance(mapping, cls):
            return mapping
        return cls(mapping)

    def insert(self, key, value):
        new = HashTrieMap(self)
        dict.__setitem__(new, key, value)
        return new

    def remove(self, key):
        new = HashTrieMap(self)
        dict.pop(new, key, None)
        return new

    def update(self, *args, **kwargs):
        """Return a NEW HashTrieMap with updates applied (immutable API)."""
        new = HashTrieMap(self)
        dict.update(new, *args, **kwargs)
        return new

    def evolve(self, **kwargs):
        new = HashTrieMap(self)
        dict.update(new, kwargs)
        return new


class HashTrieSet(frozenset):
    """Immutable set — insert/remove return new instances."""

    def insert(self, value):
        return HashTrieSet(self | {value})

    def remove(self, value):
        return HashTrieSet(self - {value})

    def update(self, *others):
        result = set(self)
        for o in others:
            result.update(o)
        return HashTrieSet(result)

    @classmethod
    def convert(cls, iterable):
        if iterable is None:
            return cls()
        if isinstance(iterable, cls):
            return iterable
        return cls(iterable)


class List(tuple):
    """Immutable list — push/drop return new instances."""

    def push_front(self, value):
        return List((value,) + self)

    def push_back(self, value):
        return List(self + (value,))

    def drop_first(self):
        return List(self[1:])

    def first(self):
        return self[0] if self else None

    def rest(self):
        return List(self[1:])

    @classmethod
    def convert(cls, iterable):
        if iterable is None:
            return cls()
        if isinstance(iterable, cls):
            return iterable
        return cls(iterable)
