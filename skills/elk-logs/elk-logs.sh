#!/usr/bin/env bash
# Read-only log search on Kibana (prod/dev) via /api/console/proxy.
# Credentials: ~/.config/elk-logs/env (chmod 600), see SKILL.md.
set -euo pipefail

CONF="${ELK_LOGS_CONF:-$HOME/.config/elk-logs/env}"
[[ -f "$CONF" ]] && source "$CONF"

usage() {
  cat <<'EOF'
Usage:
  elk-logs.sh <prod|dev> views   [filter]               # list Kibana data views (index patterns)
  elk-logs.sh <prod|dev> indices [pattern]              # _cat/indices (needs monitor privilege)
  elk-logs.sh <prod|dev> fields  [index]                # list field names of an index
  elk-logs.sh <prod|dev> search  "<query>" [options]    # Lucene query_string search
      --since 2h|30m|1d        (default 1h)   time window ending now
      --from ISO --to ISO      absolute window (overrides --since)
      --service NAME           repo/service name -> index from ELK_<ENV>_INDEX_PATTERN ({service} placeholder)
      --index PATTERN          explicit index (overrides --service)
                               default: service = current git repo name, else $ELK_<ENV>_INDEX
      --size N                 (default 50, max 500)
      --asc                    oldest first (default newest first)
      --json                   print raw hits _source as JSON lines
  elk-logs.sh <prod|dev> count   "<query>" [--since ..] [--index ..]
EOF
  exit 1
}

[[ $# -lt 2 ]] && usage
ENV="$1"; CMD="$2"; shift 2

case "$ENV" in
  prod) PFX=PROD ;;
  dev)  PFX=DEV  ;;
  *) usage ;;
esac

url_var="ELK_${PFX}_URL"; pat_var="ELK_${PFX}_INDEX_PATTERN"
BASE="${!url_var:-}"
if [[ -z "$BASE" ]]; then
  echo "Missing Kibana URL: set $url_var in $CONF" >&2; exit 2
fi
BASE="${BASE%/}"

apikey_var="ELK_${PFX}_API_KEY"; user_var="ELK_${PFX}_USER"; pass_var="ELK_${PFX}_PASS"; idx_var="ELK_${PFX}_INDEX"
if [[ -n "${!apikey_var:-}" ]]; then
  AUTH=(-H "Authorization: ApiKey ${!apikey_var}")
elif [[ -n "${!user_var:-}" && -n "${!pass_var:-}" ]]; then
  AUTH=(-u "${!user_var}:${!pass_var}")
else
  echo "Missing credentials: set $apikey_var or $user_var/$pass_var in $CONF" >&2; exit 2
fi
# Index pattern per service comes from env, e.g. ELK_PROD_INDEX_PATTERN="prefix-{service}-*"
svc_index() {
  local pat="${!pat_var:-}"
  if [[ -z "$pat" ]]; then echo "Missing index pattern: set $pat_var in $CONF (use {service} as placeholder), or pass --index" >&2; exit 2; fi
  echo "${pat//\{service\}/$1}"
}
REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || true)
if [[ -n "$REPO" && -n "${!pat_var:-}" ]]; then DEFAULT_INDEX=$(svc_index "$REPO"); else DEFAULT_INDEX="${!idx_var:-*}"; fi

# Only read-only ES endpoints are allowed through the proxy.
es() { # es <METHOD> <path> [json-body]
  local method="$1" path="$2" body="${3:-}"
  case "$path" in
    _cat/indices*|*/_search*|_search*|*/_count*|*/_mapping*|_resolve/index/*) ;;
    *) echo "Refused non read-only path: $path" >&2; exit 3 ;;
  esac
  local url="$BASE/api/console/proxy?path=$(jq -rn --arg p "$path" '$p|@uri')&method=$method"
  curl -sS -m 60 --fail-with-body -X POST "${AUTH[@]}" -H 'kbn-xsrf: true' \
    -H 'Content-Type: application/json' ${body:+--data-binary "$body"} "$url"
}

time_range() { # -> JSON range clause
  if [[ -n "$FROM" ]]; then
    jq -cn --arg f "$FROM" --arg t "${TO:-now}" '{range:{"@timestamp":{gte:$f,lte:$t}}}'
  else
    jq -cn --arg s "$SINCE" '{range:{"@timestamp":{gte:("now-"+$s),lte:"now"}}}'
  fi
}

parse_opts() {
  SINCE=1h FROM="" TO="" INDEX="$DEFAULT_INDEX" SIZE=50 ORDER=desc RAW=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) SINCE="$2"; shift 2 ;;
      --from)  FROM="$2"; shift 2 ;;
      --to)    TO="$2"; shift 2 ;;
      --index) INDEX="$2"; shift 2 ;;
      --service) INDEX=$(svc_index "$2"); shift 2 ;;
      --size)  SIZE="$2"; shift 2 ;;
      --asc)   ORDER=asc; shift ;;
      --json)  RAW=1; shift ;;
      *) echo "Unknown option $1" >&2; usage ;;
    esac
  done
  (( SIZE > 500 )) && SIZE=500 || true
}

case "$CMD" in
  views)
    curl -sS -m 30 --fail-with-body "${AUTH[@]}" "$BASE/api/data_views" \
      | jq -r --arg f "${1:-}" '.data_view[] | .title | select(contains($f))' | sort -u ;;
  indices)
    es GET "_cat/indices/${1:-*}?v&s=index&h=index,docs.count,store.size,creation.date.string" ;;
  fields)
    es GET "${1:-$DEFAULT_INDEX}/_mapping" \
      | jq -r '[.[] | .mappings | paths(objects) | map(select(. != "properties")) | join(".")] | unique[] | select(length>0)' ;;
  count|search)
    [[ $# -lt 1 ]] && usage
    Q="$1"; shift; parse_opts "$@"
    BODY=$(jq -cn --arg q "$Q" --argjson r "$(time_range)" --argjson n "$SIZE" --arg o "$ORDER" --arg c "$CMD" '
      {query:{bool:{filter:[$r,{query_string:{query:$q,default_operator:"AND",analyze_wildcard:true}}]}}}
      + (if $c=="search" then {size:$n, sort:[{"@timestamp":$o}], track_total_hits:true} else {} end)')
    if [[ "$CMD" == count ]]; then
      es GET "$INDEX/_count" "$BODY" | jq '.count'; exit 0
    fi
    RES=$(es GET "$INDEX/_search" "$BODY")
    echo "# index=$INDEX" >&2
    echo "$RES" | jq -r '"# total=\(.hits.total.value // .hits.total) shown=\(.hits.hits|length)"' >&2
    if (( RAW )); then
      echo "$RES" | jq -c '.hits.hits[] | {_index} + ._source'
    else
      echo "$RES" | jq -r '.hits.hits[] | ._source as $s
        | "[\($s["@timestamp"])] {\(._index)} \($s.host.name // $s.beat.hostname // $s.host // "")\n\($s.message // ($s|tostring))\n"'
    fi ;;
  *) usage ;;
esac
