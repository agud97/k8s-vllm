# Inventory

Machine-readable host definitions, group variables, and role metadata for the lab cluster topology.

Operational notes:

- host-specific SSH users must remain host-specific; do not override them globally when mixed access methods are used
- control-plane `access_ip` values are required when worker nodes can reach the API only through public IPs
- GPU inventory must be treated as dynamic enough to support node replacement without hard-coded assumptions in validation scripts
