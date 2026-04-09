# Avon - Client Reference

## Quick Reference

| Item | Value |
|------|-------|
| **Docker port** | 3001 |
| **Container** | pyr-avon |
| **Redis DB** | 2 |
| **MySQL DB** | pyr_avon_dev |
| **MongoDB** | pyr_avon_development |
| **Company code** | avon |
| **Business period** | bi-weekly |

## Paths

- **Client code:** `/home/kalyan/platform/clients/avon/pyr/clients/avon/`
- **DB diagrams:** `/home/kalyan/platform/clients/avon/pyr/db_diagrams/`
- **Schema:** `/home/kalyan/platform/clients/avon/pyr/clients/avon/db/schema.rb`
- **Config:** `/home/kalyan/platform/clients/avon/pyr/clients/avon/config/config.yml`
- **Routes:** `/home/kalyan/platform/clients/avon/pyr/clients/avon/config/routes.rb`

## Run Commands

```bash
cd ~/pyr-docker && ./pyr.sh up avon        # Start
cd ~/pyr-docker && ./pyr.sh down avon      # Stop
cd ~/pyr-docker && ./pyr.sh logs avon      # Tail logs
cd ~/pyr-docker && ./pyr.sh console avon   # Rails console
cd ~/pyr-docker && ./pyr.sh bash avon      # Shell into container
cd ~/pyr-docker && ./pyr.sh restart avon   # Restart
```

## Engines Loaded

PyrCore, PyrCRM, PyrShop, PyrCommunity, PyrPWP, PyrTree, PyrRules

## Key Features

- Goal card levels management
- RPS calendar functionality
- Social media scheduling (Twitter, Facebook, Instagram, X, LinkedIn, Pinterest)
- eStore integration
- Magnolia and WebOffice integrations
- Personal web pages and microsites (single-page template)
- Color confidence tables
- Downline contact management

## Database Diagrams

See `/home/kalyan/platform/clients/avon/pyr/db_diagrams/`:
- `mysql_schema_diagram.md` — Full ERD (200+ tables, Mermaid format)
- `mongodb_collections.md` — 15 MongoDB collections with document schemas
- `sql_queries.md` — Production-ready SQL queries
- `database_overview.md` — Architecture overview
- `client_specific_notes.md` — Client integration details
