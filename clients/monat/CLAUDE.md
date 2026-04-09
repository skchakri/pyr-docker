# Monat - Client Reference

## Quick Reference

| Item | Value |
|------|-------|
| **Docker port** | 3004 |
| **Container** | pyr-monat |
| **Redis DB** | 4 |
| **MySQL DB** | pyr_monat_dev |
| **MongoDB** | pyr_monat_development |
| **Company code** | monat |

## Paths

- **Client code:** `/home/kalyan/platform/clients/monat/pyr/clients/monat/`
- **DB diagrams:** `/home/kalyan/platform/clients/monat/pyr/db_diagrams/`
- **Config:** Core Pyr framework (no client-specific config)

## Run Commands

```bash
cd ~/pyr-docker && ./pyr.sh up monat        # Start
cd ~/pyr-docker && ./pyr.sh down monat      # Stop
cd ~/pyr-docker && ./pyr.sh logs monat      # Tail logs
cd ~/pyr-docker && ./pyr.sh console monat   # Rails console
cd ~/pyr-docker && ./pyr.sh bash monat      # Shell into container
cd ~/pyr-docker && ./pyr.sh restart monat   # Restart
```

## Engines Loaded

PyrCore, PyrCRM, PyrShop, PyrCommunity, PyrPWP, PyrTree

## Notes

Monat is an **ultra-minimal client** — only 2 custom files:
- `app/overrides/spree/shared/_taxonomies/add_market_to_taxonomies_cache_key.rb` — Adds market/price_type to taxonomy cache key
- `db/patch/20190418105501_add_skip_skus_for_reorder_to_app_setting.rb` — Sets skip SKUs for reorder

All other behavior comes from the core Pyr framework.

## Database Diagrams

See `/home/kalyan/platform/clients/monat/pyr/db_diagrams/`:
- `mysql_schema_diagram.md` — Full ERD (200+ tables, Mermaid format)
- `mongodb_collections.md` — 15 MongoDB collections with document schemas
- `sql_queries.md` — Production-ready SQL queries
- `database_overview.md` — Architecture overview
- `client_specific_notes.md` — Client integration details
