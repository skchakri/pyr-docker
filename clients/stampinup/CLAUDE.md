# Stampin' Up - Client Reference

## Quick Reference

| Item | Value |
|------|-------|
| **Docker port** | 3003 |
| **Container** | pyr-stampinup |
| **Redis DB** | 0 |
| **MySQL DB** | pyr_stampinup_dev |
| **MongoDB** | pyr_stampinup_development |
| **Company code** | stampinup |

## Paths

- **Client code:** `/home/kalyan/platform/clients/stampinup/pyr/clients/stampinup/`
- **DB diagrams:** `/home/kalyan/platform/clients/stampinup/pyr/db_diagrams/`
- **Schema:** `/home/kalyan/platform/clients/stampinup/pyr/clients/stampinup/db/schema.rb`
- **Config:** `/home/kalyan/platform/clients/stampinup/pyr/clients/stampinup/config/config.yml`
- **Routes:** `/home/kalyan/platform/clients/stampinup/pyr/clients/stampinup/config/routes.rb`

## Run Commands

```bash
cd ~/pyr-docker && ./pyr.sh up stampinup        # Start
cd ~/pyr-docker && ./pyr.sh down stampinup      # Stop
cd ~/pyr-docker && ./pyr.sh logs stampinup      # Tail logs
cd ~/pyr-docker && ./pyr.sh console stampinup   # Rails console
cd ~/pyr-docker && ./pyr.sh bash stampinup      # Shell into container
cd ~/pyr-docker && ./pyr.sh restart stampinup   # Restart
```

## Engines Loaded

PyrCore, PyrCRM, PyrShop, PyrCommunity, PyrPWP, PyrTree, PyrRules, Cms, Connections

## Key Features

- Stampin' Up SOAP web service integration (demonstrator auth, customer manager, lead management)
- Demonstrator authentication (Base64 auth with OEX IDs)
- Multi-source contact import (Esuite + Stampin' Up native)
- QR code generation
- User review system for events/resources
- Social media scheduling with platform-specific limits
- Esuite PWP creation and sync jobs
- Resource library with file staging and analytics
- 90-day inactive site renaming policy

## Database Diagrams

See `/home/kalyan/platform/clients/stampinup/pyr/db_diagrams/`:
- `mysql_schema_diagram.md` — Full ERD (200+ tables, Mermaid format)
- `mongodb_collections.md` — 15 MongoDB collections with document schemas
- `sql_queries.md` — Production-ready SQL queries
- `database_overview.md` — Architecture overview
- `client_specific_notes.md` — Client integration details
