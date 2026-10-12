"""Safely summarize 1C OData service metadata without returning full schema XML."""

from __future__ import annotations

from defusedxml import ElementTree as safe_xml


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def inspect_metadata(xml_data: bytes, *, limit: int = 50) -> dict:
    if not 1 <= limit <= 100:
        raise ValueError("limit must be between 1 and 100")
    root = safe_xml.fromstring(xml_data)
    schemas: list[str] = []
    types: dict[str, dict] = {}
    entities: list[dict] = []

    for schema in root.iter():
        if _local(schema.tag) != "Schema":
            continue
        ns = schema.attrib.get("Namespace", "")
        schemas.append(ns)
        for element in schema:
            if _local(element.tag) == "EntityType":
                name = element.attrib.get("Name", "")
                properties = [
                    child.attrib.get("Name", "")
                    for child in element
                    if _local(child.tag) == "Property"
                ]
                types[f"{ns}.{name}"] = {"property_count": len(properties)}
            elif _local(element.tag) == "EntityContainer":
                for child in element:
                    if _local(child.tag) == "EntitySet":
                        entities.append({
                            "name": child.attrib.get("Name", ""),
                            "entity_type": child.attrib.get("EntityType", ""),
                        })
    if not schemas:
        raise ValueError("No OData Schema found in metadata")
    for item in entities:
        item.update(types.get(item["entity_type"], {}))
    entities.sort(key=lambda e: e["name"])
    return {
        "schema_count": len(schemas),
        "entity_type_count": len(types),
        "entity_set_count": len(entities),
        "entities": entities[:limit],
        "truncated": len(entities) > limit,
    }
