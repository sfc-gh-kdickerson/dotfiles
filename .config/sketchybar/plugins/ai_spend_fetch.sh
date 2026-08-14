#!/usr/bin/env bash
# Real query against Snowhouse, via the `snow` CLI (key-pair auth against the
# `snowhouse` connection in ~/.snowflake/connections.toml — non-interactive, no
# browser SSO prompt). Must print one JSON object:
#   {"daily":{"total_usd":<num>,"by_model":{"<model>":<num>,...}},
#    "weekly":{"total_usd":<num>,"by_model":{"<model>":<num>,...}}}
set -euo pipefail

EMAIL="kaleb.dickerson@snowflake.com"
TABLE="SNOWSCIENCE.ENGINEERING_SYSTEMS.AI_USAGE_DAILY_TOKEN_COST"

# Bind explicit local-calendar-date literals instead of Snowflake's CURRENT_DATE(),
# which resolves in the session/server timezone (UTC) — that rolls over to "tomorrow"
# hours before local midnight, which would make "today's spend" read as $0 every
# evening even though real usage happened today.
LOCAL_TODAY="$(date +%Y-%m-%d)"
DOW="$(date +%u)" # 1=Monday..7=Sunday
LOCAL_WEEK_START="$(date -v-$((DOW - 1))d +%Y-%m-%d)"

ROWS_JSON="$(snow sql -c snowhouse --format json -q "
WITH base AS (
    SELECT
        DATE,
        COST_MODEL_INFO_CORTEX_CODE,
        COST_MODEL_INFO_CLAUDE_CODE_CWS_SAMPLE,
        COST_MODEL_INFO_CORTEX_REST,
        COST_MODEL_INFO_CURSOR,
        TOTAL_COST_USD_ALL_TOOLS
    FROM ${TABLE}
    WHERE EMAIL = '${EMAIL}'
      AND DATE >= DATE '${LOCAL_WEEK_START}'
      AND DATE <= DATE '${LOCAL_TODAY}'
),
totals AS (
    SELECT
        SUM(CASE WHEN DATE = DATE '${LOCAL_TODAY}' THEN TOTAL_COST_USD_ALL_TOOLS ELSE 0 END) AS daily_total,
        SUM(TOTAL_COST_USD_ALL_TOOLS) AS weekly_total
    FROM base
),
cortex_code_m AS (
    SELECT DATE, f.key AS model, f.value::FLOAT AS cost
    FROM base b, LATERAL FLATTEN(input => b.COST_MODEL_INFO_CORTEX_CODE) f
),
cws_m AS (
    SELECT DATE, f.key AS model, f.value::FLOAT AS cost
    FROM base b, LATERAL FLATTEN(input => b.COST_MODEL_INFO_CLAUDE_CODE_CWS_SAMPLE) f
),
rest_m AS (
    SELECT DATE, f.key AS model, f.value::FLOAT AS cost
    FROM base b, LATERAL FLATTEN(input => b.COST_MODEL_INFO_CORTEX_REST) f
),
cursor_m AS (
    SELECT DATE, f.key AS model, f.value::FLOAT AS cost
    FROM base b, LATERAL FLATTEN(input => b.COST_MODEL_INFO_CURSOR) f
),
all_models AS (
    SELECT * FROM cortex_code_m
    UNION ALL SELECT * FROM cws_m
    UNION ALL SELECT * FROM rest_m
    UNION ALL SELECT * FROM cursor_m
)
SELECT 'total' AS row_type, NULL AS model, (SELECT daily_total FROM totals) AS daily_val, (SELECT weekly_total FROM totals) AS weekly_val
UNION ALL
SELECT 'model' AS row_type, model,
    SUM(CASE WHEN DATE = DATE '${LOCAL_TODAY}' THEN cost ELSE 0 END) AS daily_val,
    SUM(cost) AS weekly_val
FROM all_models
GROUP BY model
ORDER BY row_type, model
")"

echo "$ROWS_JSON" | jq -c '
    . as $rows
    | ($rows[] | select(.ROW_TYPE == "total")) as $t
    | {
        daily: {
            total_usd: ($t.DAILY_VAL // 0),
            by_model: ([$rows[] | select(.ROW_TYPE == "model" and ((.DAILY_VAL // 0) > 0))]
                | map({(.MODEL): .DAILY_VAL}) | add // {})
        },
        weekly: {
            total_usd: ($t.WEEKLY_VAL // 0),
            by_model: ([$rows[] | select(.ROW_TYPE == "model" and ((.WEEKLY_VAL // 0) > 0))]
                | map({(.MODEL): .WEEKLY_VAL}) | add // {})
        }
    }
'
