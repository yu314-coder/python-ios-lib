"""jsonschema_specifications — JSON Schema meta-schema registry for iOS.

Provides REGISTRY that maps schema URIs to their meta-schema contents.
Uses a lightweight self-contained wrapper (no referencing import at module level)
to avoid circular imports with jsonschema.
"""

__version__ = "2024.10.1"

# Meta-schemas must be permissive (no type constraints) — they exist solely
# so URI lookups resolve. Real validation uses the Validator classes.
_METASCHEMAS = {
    "http://json-schema.org/draft-03/schema#": {
        "id": "http://json-schema.org/draft-03/schema#",
    },
    "http://json-schema.org/draft-04/schema#": {
        "id": "http://json-schema.org/draft-04/schema#",
    },
    "http://json-schema.org/draft-06/schema#": {
        "$id": "http://json-schema.org/draft-06/schema#",
    },
    "http://json-schema.org/draft-07/schema#": {
        "$id": "http://json-schema.org/draft-07/schema#",
    },
    "https://json-schema.org/draft/2019-09/schema": {
        "$id": "https://json-schema.org/draft/2019-09/schema",
    },
    "https://json-schema.org/draft/2020-12/schema": {
        "$id": "https://json-schema.org/draft/2020-12/schema",
    },
}


class _SpecResource:
    """Lightweight Resource wrapper matching referencing.Resource interface."""
    def __init__(self, schema):
        self._contents = schema
    @property
    def contents(self):
        return self._contents
    def id(self):
        return self._contents.get("$id") or self._contents.get("id", "")


class _SpecRegistry:
    """Self-contained Registry matching referencing.Registry interface.

    Provides combine(), contents(), items(), with_resources(), with_resource()
    without importing referencing at module level (breaks circular imports).
    """
    def __init__(self, schemas=None):
        self._schemas = dict(schemas) if schemas else {}

    def _lookup(self, uri):
        """Look up URI with and without trailing #."""
        if uri in self._schemas:
            return self._schemas[uri]
        stripped = uri.rstrip("#")
        if stripped in self._schemas:
            return self._schemas[stripped]
        if stripped + "#" in self._schemas:
            return self._schemas[stripped + "#"]
        return None

    def contents(self, uri):
        result = self._lookup(uri)
        if result is not None:
            return result
        raise KeyError(uri)

    def __getitem__(self, uri):
        result = self._lookup(uri)
        if result is not None:
            return _SpecResource(result)
        raise KeyError(uri)

    def __contains__(self, uri):
        return self._lookup(uri) is not None

    def __iter__(self):
        return iter(self._schemas)

    def __len__(self):
        return len(self._schemas)

    def items(self):
        return [(uri, _SpecResource(s)) for uri, s in self._schemas.items()]

    def combine(self, other=None, *args, **kwargs):
        """Combine with another registry → real referencing.Registry."""
        import referencing
        import referencing.jsonschema
        pairs = []
        for uri, schema in self._schemas.items():
            resource = referencing.Resource.from_contents(
                schema, default_specification=referencing.jsonschema.DRAFT202012
            )
            pairs.append((uri, resource))
        result = referencing.Registry().with_resources(pairs)
        if other is not None and hasattr(other, '__iter__'):
            try:
                for uri in other:
                    try:
                        result = result.with_resource(uri, other[uri])
                    except Exception:
                        pass
            except Exception:
                pass
        return result

    def with_resources(self, pairs):
        new_schemas = dict(self._schemas)
        for uri, resource in pairs:
            if hasattr(resource, 'contents'):
                new_schemas[uri] = resource.contents
            else:
                new_schemas[uri] = resource
        return _SpecRegistry(new_schemas)

    def with_resource(self, uri, resource):
        return self.with_resources([(uri, resource)])


REGISTRY = _SpecRegistry(_METASCHEMAS)
