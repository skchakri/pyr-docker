# Nature's Sunshine - Client Reference

## Quick Reference

| Item | Value |
|------|-------|
| **Docker port** | 3002 |
| **Container** | pyr-naturessunshine |
| **Redis DB** | 3 |
| **MySQL DB** | pyr_naturessunshine_dev |
| **MongoDB** | pyr_naturessunshine_development |
| **Company code** | naturessunshine |

## Paths

- **Client code:** `/home/kalyan/platform/clients/naturessunshine/pyr/clients/naturessunshine/`
- **DB diagrams:** `/home/kalyan/platform/clients/naturessunshine/pyr/db_diagrams/`
- **Schema:** `/home/kalyan/platform/clients/naturessunshine/pyr/clients/naturessunshine/db/schema.rb`
- **Config:** `/home/kalyan/platform/clients/naturessunshine/pyr/clients/naturessunshine/config/config.yml`
- **Routes:** `/home/kalyan/platform/clients/naturessunshine/pyr/clients/naturessunshine/config/routes.rb`

## Run Commands

```bash
cd ~/pyr-docker && ./pyr.sh up naturessunshine        # Start
cd ~/pyr-docker && ./pyr.sh down naturessunshine      # Stop
cd ~/pyr-docker && ./pyr.sh logs naturessunshine      # Tail logs
cd ~/pyr-docker && ./pyr.sh console naturessunshine   # Rails console
cd ~/pyr-docker && ./pyr.sh bash naturessunshine      # Shell into container
cd ~/pyr-docker && ./pyr.sh restart naturessunshine   # Restart
```

## Engines Loaded

PyrCore, PyrCRM, PyrShop, PyrCommunity, PyrPWP, PyrTree, PyrRules, Cms, Connections

## Key Features

- 33 incentive program widgets (Destination Paradise, Caribbean Cruise, Wellness Retreats, etc.)
- 8 LATAM market support (CO, DO, EC, SV, GT, HN, MX, PA)
- Compliance training acknowledgement (US market)
- Recognition system with certificates and roadmap
- SOAP locate_distributor_service
- GameSQS gamification, Google Maps, PayQuicker integrations
- Unity migration

## Database Diagrams

See `/home/kalyan/platform/clients/naturessunshine/pyr/db_diagrams/`:
- `mysql_schema_diagram.md` — Full ERD (200+ tables, Mermaid format)
- `mongodb_collections.md` — 15 MongoDB collections with document schemas
- `sql_queries.md` — Production-ready SQL queries
- `database_overview.md` — Architecture overview
- `client_specific_notes.md` — Client integration details
