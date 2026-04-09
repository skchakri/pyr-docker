#!/usr/bin/env bash
#
# extract_prod.sh — Export minimal dev dataset from production via SSH tunnel
#
# Usage:
#   ./extract_prod.sh <client> <db_host> <db_name> <db_user> <db_pass> [mongo_uri]
#
# Prerequisites:
#   - SSH tunnel to RDS already established (e.g., ssh -L 3307:rds-host:3306 bastion)
#   - mysql client installed locally
#   - mongoexport installed if exporting MongoDB collections
#
# Example:
#   ssh -L 3307:avon-prod.rds.amazonaws.com:3306 bastion-host &
#   ./extract_prod.sh avon 127.0.0.1:3307 pyr_avon_production dbuser dbpass \
#     "mongodb://user:pass@localhost:27117/pyr_avon_production?ssl=true&authSource=admin"
#
set -euo pipefail

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <client> <db_host> <db_name> <db_user> <db_pass> [mongo_uri]"
  echo ""
  echo "  db_host can include port: 127.0.0.1:3307"
  exit 1
fi

CLIENT="$1"
DB_HOST_PORT="$2"
DB_NAME="$3"
DB_USER="$4"
DB_PASS="$5"
MONGO_URI="${6:-}"

# Parse host:port
DB_HOST="${DB_HOST_PORT%%:*}"
DB_PORT="${DB_HOST_PORT##*:}"
if [[ "$DB_PORT" == "$DB_HOST" ]]; then
  DB_PORT=3306
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/data/${CLIENT}"

mkdir -p "$DATA_DIR"

MYSQL_CMD="mysql --default-character-set=utf8mb4 -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} -N --batch"

# Helper: export a full table to TSV
export_table() {
  local table="$1"
  echo "  Exporting ${table}..."
  $MYSQL_CMD -e "SELECT * FROM ${table}" > "${DATA_DIR}/${table}.tsv" 2>/dev/null || {
    echo "  WARNING: Table ${table} not found or empty, skipping."
    rm -f "${DATA_DIR}/${table}.tsv"
  }
}

# Helper: export with custom query to TSV
export_query() {
  local name="$1"
  local query="$2"
  echo "  Exporting ${name}..."
  $MYSQL_CMD -e "${query}" > "${DATA_DIR}/${name}.tsv" 2>/dev/null || {
    echo "  WARNING: Query for ${name} failed, skipping."
    rm -f "${DATA_DIR}/${name}.tsv"
  }
}

echo "================================================"
echo "Extracting minimal dev dataset for: ${CLIENT}"
echo "Database: ${DB_NAME} @ ${DB_HOST}:${DB_PORT}"
echo "Output:   ${DATA_DIR}/"
echo "================================================"
echo ""

# --- Group 1: Lookup/config tables (full dump, no PII) ---
echo "[Group 1] Lookup & config tables..."

GROUP1_TABLES=(
  tree_user_types tree_user_statuses tree_ranks tree_rank_definitions
  tree_period_types tree_bonus_types tree_commission_run_statuses
  pyr_security_groups pyr_widgets pyr_widget_pages pyr_widget_page_widgets
  pyr_subscription_plans pyr_market_languages pyr_resources pyr_company_news
  spree_countries spree_states spree_zones spree_zone_members
  spree_tax_categories spree_shipping_categories spree_payment_methods
  spree_stores spree_roles spree_taxonomies spree_taxons
  spree_products spree_variants spree_prices spree_option_types
  spree_option_values spree_properties spree_product_properties
  spree_preferences spree_promotions spree_stock_locations
)

for table in "${GROUP1_TABLES[@]}"; do
  export_table "$table"
done

echo ""

# --- Group 2: Tree/User data (full dump) ---
echo "[Group 2] Tree/User data..."

GROUP2_TABLES=(
  tree_users tree_sponsors tree_placements
  tree_user_plus tree_user_summary tree_dynamic_field_mappings
)

for table in "${GROUP2_TABLES[@]}"; do
  export_table "$table"
done

echo ""

# --- Group 3: Auth/Profile data (full dump) ---
echo "[Group 3] Auth/Profile data..."

GROUP3_TABLES=(
  users pyr_profiles pyr_addresses pyr_security_groups_users
)

for table in "${GROUP3_TABLES[@]}"; do
  export_table "$table"
done

echo ""

# --- Group 4: Period-filtered data (last 3 periods per period_type) ---
echo "[Group 4] Period-filtered data (last 3 per period_type)..."

# Subquery to get last 3 period IDs per period_type
PERIOD_FILTER="id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY period_type_id ORDER BY end_date DESC) AS rn
    FROM tree_periods
  ) ranked WHERE rn <= 3
)"

export_query "tree_periods" "SELECT * FROM tree_periods WHERE ${PERIOD_FILTER}"

export_query "tree_period_data" "SELECT pd.* FROM tree_period_data pd WHERE pd.period_id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY period_type_id ORDER BY end_date DESC) AS rn
    FROM tree_periods
  ) ranked WHERE rn <= 3
)"

export_query "tree_period_data_plus" "SELECT pdp.* FROM tree_period_data_plus pdp WHERE pdp.period_id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY period_type_id ORDER BY end_date DESC) AS rn
    FROM tree_periods
  ) ranked WHERE rn <= 3
)"

export_query "tree_commission_runs" "SELECT cr.* FROM tree_commission_runs cr WHERE cr.period_id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY period_type_id ORDER BY end_date DESC) AS rn
    FROM tree_periods
  ) ranked WHERE rn <= 3
)"

export_query "tree_commissions" "SELECT c.* FROM tree_commissions c WHERE c.commission_run_id IN (
  SELECT cr.id FROM tree_commission_runs cr WHERE cr.period_id IN (
    SELECT id FROM (
      SELECT id, ROW_NUMBER() OVER (PARTITION BY period_type_id ORDER BY end_date DESC) AS rn
      FROM tree_periods
    ) ranked WHERE rn <= 3
  )
)"

echo ""

# --- Group 5: CRM contacts (filtered to users with tree records) ---
echo "[Group 5] CRM contacts (for users with tree records)..."

export_query "pyr_contacts" "SELECT c.* FROM pyr_contacts c
  WHERE c.tree_user_id IS NOT NULL
     OR c.user_id IN (SELECT u.id FROM users u INNER JOIN tree_users tu ON tu.user_id = u.id)"

export_query "pyr_contact_emails" "SELECT ce.* FROM pyr_contact_emails ce
  WHERE ce.contact_id IN (
    SELECT c.id FROM pyr_contacts c
    WHERE c.tree_user_id IS NOT NULL
       OR c.user_id IN (SELECT u.id FROM users u INNER JOIN tree_users tu ON tu.user_id = u.id)
  )"

export_query "pyr_contact_phone_numbers" "SELECT cpn.* FROM pyr_contact_phone_numbers cpn
  WHERE cpn.contact_id IN (
    SELECT c.id FROM pyr_contacts c
    WHERE c.tree_user_id IS NOT NULL
       OR c.user_id IN (SELECT u.id FROM users u INNER JOIN tree_users tu ON tu.user_id = u.id)
  )"

echo ""

# --- Export column headers for each TSV ---
echo "[Headers] Exporting column names..."
for tsv_file in "${DATA_DIR}"/*.tsv; do
  [ -f "$tsv_file" ] || continue
  table_name="$(basename "$tsv_file" .tsv)"
  $MYSQL_CMD -e "SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION SEPARATOR '\t')
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_NAME='${table_name}'" \
    > "${DATA_DIR}/${table_name}.cols" 2>/dev/null || true
done

echo ""

# --- MongoDB collections ---
if [[ -n "$MONGO_URI" ]]; then
  echo "[MongoDB] Exporting collections..."
  mongoexport --uri="$MONGO_URI" --collection=pyr_rules_rules \
    --out="${DATA_DIR}/pyr_rules_rules.json" 2>/dev/null || echo "  WARNING: pyr_rules_rules export failed"
  mongoexport --uri="$MONGO_URI" --collection=pyr_rules_actions \
    --out="${DATA_DIR}/pyr_rules_actions.json" 2>/dev/null || echo "  WARNING: pyr_rules_actions export failed"
  echo ""
fi

# --- Summary ---
echo "================================================"
echo "Export complete for: ${CLIENT}"
echo ""
FILE_COUNT=$(find "$DATA_DIR" -name "*.tsv" | wc -l)
TOTAL_SIZE=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
echo "  TSV files: ${FILE_COUNT}"
echo "  Total size: ${TOTAL_SIZE}"
echo "  Location: ${DATA_DIR}/"
echo ""
echo "Next step: copy data/ to dev machine and run:"
echo "  ./import_dev.sh ${CLIENT}"
echo "================================================"
