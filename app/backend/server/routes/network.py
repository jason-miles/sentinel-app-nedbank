"""Entity Network graph (PRD §9 page 3)."""
from fastapi import APIRouter
from ..db import fetch_all
from ..config import GOLD_SCHEMA, SILVER_SCHEMA

router = APIRouter(prefix="/api", tags=["network"])


@router.get("/network/{entity_id}")
def entity_network(entity_id: str, hops: int = 1):
    """Edges centred on an entity: its accounts + counterparties + related parties.

    Returns nodes + edges for a graph viz (Cytoscape/D3).
    """
    edges = fetch_all(f"""
SELECT source_entity_id, target_entity_id, edge_type, weight
FROM {GOLD_SCHEMA}.entity_network
WHERE source_entity_id = :eid OR target_entity_id = :eid
LIMIT 200
""", [{"name": "eid", "value": entity_id}])

    # Build node set from the edges, label with entity names where resolvable.
    node_ids = set()
    for e in edges:
        node_ids.add(e["source_entity_id"])
        node_ids.add(e["target_entity_id"])
    nodes = []
    if node_ids:
        ent_ids = [n for n in node_ids if str(n).startswith("ENT")]
        labels = {}
        if ent_ids:
            # Parameterize the IN list (:e0, :e1, …) — never interpolate ids.
            placeholders = ", ".join(f":e{i}" for i in range(len(ent_ids)))
            params = [{"name": f"e{i}", "value": v} for i, v in enumerate(ent_ids)]
            for r in fetch_all(f"""
SELECT entity_id, max(full_name) AS full_name, max(party_type) AS party_type
FROM {SILVER_SCHEMA}.entities WHERE entity_id IN ({placeholders}) GROUP BY entity_id
""", params):
                labels[r["entity_id"]] = r
        for n in node_ids:
            meta = labels.get(n, {})
            nodes.append({
                "id": n,
                "label": meta.get("full_name") or n,
                "kind": meta.get("party_type") or ("account" if str(n).startswith("ACCT:") else "other"),
            })
    return {"nodes": nodes, "edges": edges}
