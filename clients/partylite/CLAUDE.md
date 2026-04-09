# PartyLite - Client Reference

## Quick Reference

| Item | Value |
|------|-------|
| **Docker port** | 3005 |
| **Container** | pyr-partylite |
| **Redis DB** | 1 |
| **MySQL DB** | pyr_partylite_dev |
| **MongoDB** | pyr_partylite_development |
| **Company code** | partylite |

## Paths

- **Client code:** `/home/kalyan/platform/clients/partylite/pyr/clients/partylite/`
- **DB diagrams:** `/home/kalyan/platform/clients/partylite/pyr/db_diagrams/`
- **Schema:** `/home/kalyan/platform/clients/partylite/pyr/clients/partylite/db/schema.rb`
- **Config:** `/home/kalyan/platform/clients/partylite/pyr/clients/partylite/config/config.yml`
- **Routes:** `/home/kalyan/platform/clients/partylite/pyr/clients/partylite/config/routes.rb`

## Run Commands

```bash
cd ~/pyr-docker && ./pyr.sh up partylite        # Start
cd ~/pyr-docker && ./pyr.sh down partylite      # Stop
cd ~/pyr-docker && ./pyr.sh logs partylite      # Tail logs
cd ~/pyr-docker && ./pyr.sh console partylite   # Rails console
cd ~/pyr-docker && ./pyr.sh bash partylite      # Shell into container
cd ~/pyr-docker && ./pyr.sh restart partylite   # Restart
```

## Engines Loaded

PyrCore, PyrCRM, PyrShop, PyrCommunity, PyrPWP, PyrTree, PyrRules, Cms, Connections, Spree

## Key Features

- Multiple payment gateways: Worldline + Worldpay (with full callback routes)
- Gift certificate system (application, conversion, denomination)
- Direct debit payment support
- Parcellab parcel tracking integration
- Leads management with Facebook/YouTube webhooks
- Consultant locator (by location, name, city/state)
- Stash Cash financial management
- V2 enrollment workflow with payment integration
- Experian address validation/suggestions
- Coupon/promotion engine with catalog price rules and stop-sell
- Multi-market support with market-specific address fields
- PWP backoffice redirect ("mybiz")

## Database Diagrams

See `/home/kalyan/platform/clients/partylite/pyr/db_diagrams/`:
- `mysql_schema_diagram.md` — Full ERD (200+ tables, Mermaid format)
- `mongodb_collections.md` — 15 MongoDB collections with document schemas
- `sql_queries.md` — Production-ready SQL queries
- `database_overview.md` — Architecture overview
- `client_specific_notes.md` — Client integration details
