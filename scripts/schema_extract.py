def reachable_definitions(schema, roots):
    """Select a pinned schema's closed set of local $defs references."""
    selected = {}
    pending = list(roots)
    def references(value):
        if isinstance(value, dict):
            if "$ref" in value:
                ref = value["$ref"]
                if not ref.startswith("#/$defs/"):
                    raise ValueError("unsupported schema reference: " + ref)
                pending.append(ref.removeprefix("#/$defs/"))
            for child in value.values():
                references(child)
        elif isinstance(value, list):
            for child in value:
                references(child)

    while pending:
        name = pending.pop()
        if name not in selected:
            selected[name] = schema["$defs"][name]
            references(selected[name])
    return selected
