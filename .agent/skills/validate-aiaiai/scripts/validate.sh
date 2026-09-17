#!/usr/bin/env bash
# Drives a disposable copy of this repo's working tree the way the user does:
# make setup, make start, then the HTTP APIs coding agents call.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"
PORTS="4000 8888 5439"
FEATURES="setup connection-info gateway-api agent-keys web-search services secret-hygiene"
MODELS="claude-fable-5-1 claude-opus-5 claude-sonnet-5 claude-haiku-4-5-20251001 grok-4.6 gpt-5.6-sol"
# Models whose upstream publishes no cache-write price, so Copilot bills none.
# Their cache_creation_input_token_cost is a priced zero, not a missing price.
ZERO_CACHE_WRITE_MODELS="grok-4.6"
COST_FIELDS="input_cost_per_token output_cost_per_token cache_read_input_token_cost cache_creation_input_token_cost"
# Master key (sk- + 32 hex), minted agent key (sk- + 22 base64url), Bedrock and
# AWS keys from older history, GitHub tokens, Postgres URL passwords, the 48-hex
# Postgres password, 64-hex secrets.
SECRET_PATTERN='sk-[a-f0-9]{32}|sk-[A-Za-z0-9_-]{22}([^A-Za-z0-9_-]|$)|ABSK[A-Za-z0-9+/]{20,}|AKIA[0-9A-Z]{16}|gh[opsur]_[A-Za-z0-9]{36}|postgres(ql)?://[^:@/[:space:]]+:[^@/[:space:]$]+@|(^|[^a-f0-9])[a-f0-9]{48}([^a-f0-9]|$)|[a-f0-9]{64}'
# The validator has no Copilot account. This key file is valid until 2100, so
# LiteLLM never runs the device flow, and its dead API base fails any request
# that would reach Copilot.
COPILOT_FIXTURE='{"token":"validate-fixture","expires_at":4102444800,"endpoints":{"api":"http://127.0.0.1:9"}}'
DEVBOX_BIN="$(dirname "$(command -v devbox 2>/dev/null || echo /nonexistent/devbox)")"

die() { printf 'validate: %s\n' "$1" >&2; exit 2; }

usage() {
  cat >&2 <<'EOF'
usage: validate.sh run [OUT]           preflight, launch, doctor, every feature, cleanup
       validate.sh launch OUT          copy the working tree to OUT/repo, run setup, start services
       validate.sh doctor OUT          read-only health check of the instance under OUT
       validate.sh drive OUT FEATURE   FEATURE: setup connection-info gateway-api agent-keys
                                                web-search services secret-hygiene
       validate.sh cleanup OUT         stop services, delete OUT/repo, keep OUT/evidence
EOF
  exit 2
}

init_out() {
  mkdir -p "$1" || die "cannot create $1"
  OUT="$(cd "$1" && pwd)"
  REPO="$OUT/repo"
  EV="$OUT/evidence"
  REPORT="$OUT/report.tsv"
  mkdir -p "$EV"
  [[ -f "$REPORT" ]] || printf 'feature\tcheck\tresult\tevidence\n' > "$REPORT"
}

record() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >> "$REPORT"
  printf '%-16s %-40s %s\n' "$1" "$2" "$3"
}

# check FEATURE NAME EVIDENCE COMMAND...: PASS when COMMAND succeeds.
check() {
  local feature="$1" name="$2" evidence="$3"; shift 3
  if "$@"; then record "$feature" "$name" PASS "$evidence"; else record "$feature" "$name" FAIL "$evidence"; fi
}

same()      { [[ "$1" == "$2" ]]; }
not()       { ! "$@"; }
empty()     { [[ ! -s "$1" ]]; }
status_is() { [[ "$HTTP_STATUS" == "$1" ]]; }

envval() { grep -E "^export $1=" "$REPO/.envrc.local" 2>/dev/null | tail -1 | cut -d= -f2-; }
copilot_token() { cat "$REPO/data/github_copilot/access-token" 2>/dev/null; }

# Runs make in the copy with a scrubbed environment, so nothing leaks in from
# direnv or the calling shell. Prisma and npm download their CLI into OUT, not
# the user's home cache.
mk() {
  env -i HOME="$HOME" USER="${USER:-$(id -un)}" TERM=dumb \
    PRISMA_HOME_DIR="$OUT/cache" npm_config_cache="$OUT/cache/npm" \
    PATH="$DEVBOX_BIN:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    make --no-print-directory -C "$REPO" "$@"
}

py() { "$REPO/.venv/bin/python" "$@"; }

# json_is EXPR EXPECTED: evaluates EXPR against the last HTTP body bound to `d`.
json_is() {
  same "$(py -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$HTTP_BODY" "$1" 2>/dev/null)" "$2"
}

redact() {
  local args=(-e 's|^$||') s
  for s in "$(envval LITELLM_MASTER_KEY)" "$(envval SEARXNG_SECRET)" "$(envval POSTGRES_PASSWORD)" \
           "$(copilot_token)" $(cat "$REPO/.validate-keys" 2>/dev/null); do
    [[ -n "$s" ]] && args+=(-e "s|$s|<redacted>|g")
  done
  sed "${args[@]}"
}

host() { envval LITELLM_HOST; }

# http NAME METHOD PATH KEY [JSON]: evidence goes to $EV/$CUR/NAME.txt, redacted.
http() {
  local name="$1" method="$2" path="$3" key="$4" body="${5:-}"
  local url args
  url="http://$(host):4000$path"
  args=(-sS -o "$REPO/.http-body" -w '%{http_code}' -X "$method" --max-time 90)
  [[ -n "$key" ]] && args+=(-H "Authorization: Bearer $key")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' -d "$body")
  : > "$REPO/.http-body"
  HTTP_STATUS="$(curl "${args[@]}" "$url" 2> "$REPO/.http-err")" || HTTP_STATUS=000
  HTTP_BODY="$REPO/.http-body"
  {
    printf '%s %s\n' "$method" "$url"
    [[ -n "$key" ]] && printf 'Authorization: Bearer %s\n' "$key"
    [[ -n "$body" ]] && printf '\n%s\n' "$body"
    printf '\nHTTP %s\n' "$HTTP_STATUS"
    cat "$REPO/.http-body" "$REPO/.http-err"
    printf '\n'
  } | redact > "$EV/$CUR/$name.txt"
}

default_listen_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit }}'
  else
    ipconfig getifaddr "$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')"
  fi
}

listeners() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH | awk '{print $4}'
  else
    lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 {print $9}' | sort -u
  fi
}

port_busy() { listeners | grep -qE "[:.]$1\$"; }
# only_listening_on ADDR PORT: ADDR:PORT is the one and only listener on PORT.
only_listening_on() { same "$(listeners | grep -E "[:.]$2\$" | sort -u)" "$1:$2"; }

wait_ready() {
  local waited=0
  while (( waited < $1 )); do
    same "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://$(host):4000/health/liveliness")" 200 && return 0
    sleep 2; waited=$((waited + 2))
  done
  return 1
}

wait_ports_free() {
  local waited=0 p busy
  while (( waited < $1 )); do
    busy=0
    for p in $PORTS; do port_busy "$p" && busy=1; done
    (( busy == 0 )) && return 0
    sleep 1; waited=$((waited + 1))
  done
  return 1
}

failed_with_hint() { [[ "$1" -ne 0 ]] && grep -q "$3" "$2"; }
nonempty_same() { [[ -n "$1" ]] && same "$1" "$2"; }
# git grep exits 1 on no match and above 1 on error, so an error is never "clean".
no_match() { [[ "$1" -eq 1 ]] && empty "$2"; }
skipped_copilot_login() { grep -q 'Not signed in to GitHub Copilot' "$1" && not grep -q 'Please visit' "$1"; }
# The user's ~/.config/litellm is LiteLLM's default token dir. Fail only if this run created it.
config_dir_untouched() { grep -qx yes "$OUT/config-litellm-existed" 2>/dev/null || [[ ! -e "$HOME/.config/litellm" ]]; }

# Every model in MODELS carries every cost field in /model/info. Each is above
# zero, except a cache-write price for a model in ZERO_CACHE_WRITE_MODELS, whose
# upstream publishes none; there the field must be present and exactly zero.
priced_expr() {
  printf "all(any(x['model_name'] == m and all(f in x['model_info'] and (x['model_info'][f] or 0) >= 0 and ((x['model_info'][f] or 0) > 0 or (f == 'cache_creation_input_token_cost' and m in '%s'.split())) for f in '%s'.split()) for x in d['data']) for m in '%s'.split())" \
    "$ZERO_CACHE_WRITE_MODELS" "$COST_FIELDS" "$MODELS"
}

preflight() {
  [[ -x "$DEVBOX_BIN/devbox" ]] || die "devbox is not on PATH"
  [[ -e "$REPO" ]] && die "$REPO already exists; run: validate.sh cleanup $OUT"
  local p
  for p in $PORTS; do
    port_busy "$p" && die "port $p is already in use; refusing to drive an instance this run did not start"
  done
  return 0
}

cmd_launch() {
  init_out "$1"
  preflight
  LISTEN="${VALIDATE_LISTEN:-$(default_listen_ip)}"
  [[ -n "$LISTEN" ]] || die "no default-route IPv4 address; set VALIDATE_LISTEN=<ip>"
  CUR=setup; mkdir -p "$EV/$CUR"
  if [[ -e "$HOME/.config/litellm" ]]; then echo yes; else echo no; fi > "$OUT/config-litellm-existed"
  mkdir -p "$REPO"
  (cd "$SRC" && git ls-files -co --exclude-standard -z | xargs -0 tar cf -) | tar xf - -C "$REPO"
  record setup copy-working-tree PASS "$REPO"

  local rc log="$EV/setup/start-before-setup.txt"
  mk start > "$log" 2>&1; rc=$?
  check setup start-refused-before-setup "$log" failed_with_hint "$rc" "$log" "make setup"

  log="$EV/setup/fresh-setup.txt"
  printf '%s\n5\n' "$LISTEN" | mk setup > "$REPO/.setup-out" 2>&1; rc=$?
  redact < "$REPO/.setup-out" > "$log"
  check setup fresh-setup-exits-0 "$log" same "$rc" 0
  check setup setup-skips-copilot-login-without-tty "$log" skipped_copilot_login "$log"
  grep -oE '^export [A-Z_]+' "$REPO/.envrc.local" > "$EV/setup/envrc-vars.txt" 2>/dev/null
  local var
  for var in LITELLM_HOST LITELLM_MASTER_KEY LITELLM_MAX_BUDGET SEARXNG_SECRET POSTGRES_PASSWORD; do
    check setup "envrc-has-$var" "$EV/setup/envrc-vars.txt" grep -qx "export $var" "$EV/setup/envrc-vars.txt"
  done
  ls -l "$REPO/.envrc.local" | cut -c1-10 > "$EV/setup/envrc-mode.txt"
  check setup envrc-mode-600 "$EV/setup/envrc-mode.txt" grep -qx -- '-rw-------' "$EV/setup/envrc-mode.txt"
  check setup listen-address-saved "$EV/setup/envrc-vars.txt" same "$(host)" "$LISTEN"
  check setup budget-rendered "$REPO/litellm/config.yaml" grep -qE '^\s*max_budget: 5$' "$REPO/litellm/config.yaml"
  check setup postgres-initialized "$REPO/data/postgres/PG_VERSION" test -f "$REPO/data/postgres/PG_VERSION"

  (umask 077 && mkdir -p "$REPO/data/github_copilot" && printf '%s' "$COPILOT_FIXTURE" > "$REPO/data/github_copilot/api-key.json")
  log="$EV/setup/start.txt"
  mk start > "$log" 2>&1; rc=$?
  check setup start-exits-0 "$log" same "$rc" 0
  check setup start-warns-without-copilot-login "$log" grep -q 'make copilot-login' "$log"
  check setup gateway-ready-within-300s "$log" wait_ready 300
}

cmd_doctor() {
  init_out "$1"
  CUR=doctor; mkdir -p "$EV/$CUR"
  local log="$EV/doctor/status.txt" proc
  mk status > "$log" 2>&1
  for proc in postgres searxng litellm; do
    check doctor "$proc-running" "$log" grep -qE "[[:space:]]${proc}[[:space:]]+[^[:space:]]+[[:space:]]+Running[[:space:]]" "$log"
  done
  http liveliness GET /health/liveliness ""
  check doctor liveliness-200 "$EV/doctor/liveliness.txt" status_is 200
  http readiness GET /health/readiness ""
  check doctor db-connected "$EV/doctor/readiness.txt" json_is 'd["db"]' connected
  listeners > "$EV/doctor/listeners.txt"
  check doctor litellm-bound-to-listen-address "$EV/doctor/listeners.txt" only_listening_on "$(host)" 4000
  check doctor searxng-loopback-only "$EV/doctor/listeners.txt" only_listening_on 127.0.0.1 8888
  check doctor postgres-loopback-only "$EV/doctor/listeners.txt" only_listening_on 127.0.0.1 5439
}

drive_setup() {
  local before after rc log="$EV/setup/rerun-setup.txt"
  fingerprint() {
    printf '%s\n' "$(envval LITELLM_HOST)" "$(envval LITELLM_MASTER_KEY)" "$(envval LITELLM_MAX_BUDGET)" \
      "$(envval SEARXNG_SECRET)" "$(envval POSTGRES_PASSWORD)" | cksum
  }
  before="$(fingerprint)"
  printf 'export VALIDATE_CUSTOM=kept\nexport MACHINE_MODE=full\n' >> "$REPO/.envrc.local"
  printf '\n\n' | mk setup > "$REPO/.setup-out" 2>&1; rc=$?
  redact < "$REPO/.setup-out" > "$log"
  after="$(fingerprint)"
  check setup rerun-exits-0 "$log" same "$rc" 0
  check setup rerun-keeps-secrets-and-answers "$log" same "$before" "$after"
  check setup rerun-keeps-custom-lines "$log" grep -qx 'export VALIDATE_CUSTOM=kept' "$REPO/.envrc.local"
  check setup rerun-drops-retired-vars "$log" not grep -q '^export MACHINE_MODE=' "$REPO/.envrc.local"
  check setup rerun-reuses-database "$log" grep -q 'Reusing existing database' "$log"
}

drive_connection-info() {
  local log="$EV/connection-info/show-base-url.txt"
  mk show-base-url > "$log" 2>&1
  check connection-info show-base-url "$log" same "$(cat "$log")" "http://$(host):4000"
  mk show-key > "$REPO/.show-key" 2>&1
  redact < "$REPO/.show-key" > "$EV/connection-info/show-key.txt"
  check connection-info show-key-matches-master-key "$EV/connection-info/show-key.txt" \
    nonempty_same "$(cat "$REPO/.show-key")" "$(envval LITELLM_MASTER_KEY)"
}

chat_body() { printf '{"model":"claude-sonnet-5","messages":[{"role":"user","content":"ping"}],"mock_response":"pong"}'; }

# remember_key KEY EVIDENCE: adds KEY to the redaction list, then re-redacts the
# evidence file that was written before the key was known.
remember_key() {
  [[ -n "$1" ]] || return 0
  printf '%s\n' "$1" >> "$REPO/.validate-keys"
  redact < "$2" > "$2.tmp" && mv "$2.tmp" "$2"
}

drive_gateway-api() {
  local master mock m
  master="$(envval LITELLM_MASTER_KEY)"
  http models-without-key GET /v1/models ""
  check gateway-api rejects-missing-key "$EV/gateway-api/models-without-key.txt" status_is 401
  http models GET /v1/models "$master"
  check gateway-api lists-models-200 "$EV/gateway-api/models.txt" status_is 200
  for m in $MODELS; do
    check gateway-api "lists-$m" "$EV/gateway-api/models.txt" json_is "'$m' in [x['id'] for x in d['data']]" True
  done
  http model-info GET /model/info "$master"
  check gateway-api model-info-has-copilot-pricing "$EV/gateway-api/model-info.txt" json_is "$(priced_expr)" True
  # LiteLLM honors a client's mock_response only for keys whose metadata allows it.
  # Aliases must be unique, so each drive mints a fresh one.
  http mock-key POST /key/generate "$master" \
    "{\"key_alias\":\"validate-mock-$(date +%s)\",\"metadata\":{\"allow_client_mock_response\":true}}"
  mock="$(py -c 'import json,sys; print(json.load(open(sys.argv[1]))["key"])' "$HTTP_BODY" 2>/dev/null)"
  remember_key "$mock" "$EV/gateway-api/mock-key.txt"
  check gateway-api mock-key-minted "$EV/gateway-api/mock-key.txt" test -n "$mock"
  http openai-chat POST /v1/chat/completions "$mock" "$(chat_body)"
  check gateway-api openai-chat-completions "$EV/gateway-api/openai-chat.txt" json_is 'd["choices"][0]["message"]["content"]' pong
  http anthropic-messages POST /v1/messages "$mock" \
    '{"model":"claude-sonnet-5","max_tokens":16,"messages":[{"role":"user","content":"ping"}],"mock_response":"pong"}'
  check gateway-api anthropic-messages "$EV/gateway-api/anthropic-messages.txt" json_is 'd["content"][0]["text"]' pong
}

agent_key() { cat "$REPO/.validate-agent-key" 2>/dev/null; }

drive_agent-keys() {
  local out rc key master alias
  master="$(envval LITELLM_MASTER_KEY)"
  alias="validate-agent-$(date +%s)"
  out="$(mk new-key NAME="$alias" BUDGET=1 2>&1)"; rc=$?
  key="$(printf '%s\n' "$out" | grep -E '^sk-' | tail -1)"
  if [[ -n "$key" ]]; then
    printf '%s\n' "$key" >> "$REPO/.validate-keys"
    printf '%s\n' "$key" > "$REPO/.validate-agent-key"
  fi
  printf '%s\n' "$out" | redact > "$EV/agent-keys/new-key.txt"
  check agent-keys new-key-prints-key "$EV/agent-keys/new-key.txt" test "$rc" -eq 0 -a -n "$key"
  mk new-key > "$EV/agent-keys/new-key-without-name.txt" 2>&1; rc=$?
  check agent-keys new-key-requires-name "$EV/agent-keys/new-key-without-name.txt" \
    failed_with_hint "$rc" "$EV/agent-keys/new-key-without-name.txt" "usage: make new-key"
  http key-info GET "/key/info?key=$key" "$master"
  check agent-keys key-has-alias "$EV/agent-keys/key-info.txt" json_is 'd["info"]["key_alias"]' "$alias"
  check agent-keys key-has-budget "$EV/agent-keys/key-info.txt" json_is 'd["info"]["max_budget"]' 1.0
  check agent-keys key-has-30d-budget-duration "$EV/agent-keys/key-info.txt" json_is 'd["info"]["budget_duration"]' 30d
  http models-with-agent-key GET /v1/models "$key"
  check agent-keys agent-key-authenticates "$EV/agent-keys/models-with-agent-key.txt" status_is 200
  http models-with-unknown-key GET /v1/models "sk-validate-unknown"
  check agent-keys unknown-key-rejected "$EV/agent-keys/models-with-unknown-key.txt" status_is 401
}

drive_web-search() {
  http search POST /v1/search/local-search "$(agent_key)" '{"query":"Linux kernel","max_results":3}'
  check web-search search-endpoint-200 "$EV/web-search/search.txt" status_is 200
  check web-search search-returns-results "$EV/web-search/search.txt" json_is 'len(d["results"]) > 0' True
  # Claude Code's standalone web_search request. A 200 proves LiteLLM answered it
  # from SearXNG: the fixture's dead Copilot API base fails any upstream call.
  http interception POST /v1/messages "$(agent_key)" \
    '{"model":"claude-sonnet-5","max_tokens":256,"tools":[{"type":"web_search_20250305","name":"web_search","max_uses":1}],"messages":[{"role":"user","content":"Linux kernel"}]}'
  check web-search interception-200 "$EV/web-search/interception.txt" status_is 200
  check web-search websearch-interception "$EV/web-search/interception.txt" \
    json_is "d['content'][0]['type'] == 'text' and 'URL: http' in d['content'][0]['text'] and d['usage']['output_tokens'] == 0" True
  check web-search no-device-flow-in-server-log "$REPO/logs/process-compose.log" \
    not grep -q 'Please visit' "$REPO/logs/process-compose.log"
}

drive_services() {
  local rc log="$EV/services/loopback.txt"
  # 127.0.0.1 is the listen address itself, and 0.0.0.0 includes it.
  case "$(host)" in
    127.0.0.1|0.0.0.0) ;;
    *)
      printf 'GET http://127.0.0.1:4000/health/liveliness\n\nHTTP %s\n' \
        "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:4000/health/liveliness)" > "$log"
      check services loopback-not-listening "$log" grep -qx 'HTTP 000' "$log"
      ;;
  esac
  mk stop > "$EV/services/stop.txt" 2>&1; rc=$?
  check services stop-exits-0 "$EV/services/stop.txt" same "$rc" 0
  check services ports-freed-after-stop "$EV/services/stop.txt" wait_ports_free 60
  mk start > "$EV/services/restart.txt" 2>&1; rc=$?
  check services restart-exits-0 "$EV/services/restart.txt" same "$rc" 0
  check services ready-after-restart "$EV/services/restart.txt" wait_ready 300
  http key-after-restart GET /v1/models "$(agent_key)"
  check services agent-key-survives-restart "$EV/services/key-after-restart.txt" status_is 200
}

drive_secret-hygiene() {
  local path hits="$EV/secret-hygiene"
  for path in .envrc.local litellm/config.yaml searxng/settings.yml data/postgres/PG_VERSION \
              data/github_copilot/access-token logs/process-compose.log; do
    check secret-hygiene "gitignored-$path" "$SRC/.gitignore" git -C "$SRC" check-ignore -q "$path"
  done
  local excludes=(-- . ':!requirements.txt' ':!devbox.lock') rc
  git -C "$SRC" grep --untracked -nIE "$SECRET_PATTERN" "${excludes[@]}" > "$hits/worktree-hits.txt"; rc=$?
  check secret-hygiene no-secret-patterns-in-worktree "$hits/worktree-hits.txt" no_match "$rc" "$hits/worktree-hits.txt"
  git -C "$SRC" log --all -p "${excludes[@]}" | grep -nE "$SECRET_PATTERN" > "$hits/history-hits.txt"
  local st=("${PIPESTATUS[@]}")
  [[ "${st[0]}" -eq 0 ]] || st[1]=2
  check secret-hygiene no-secret-patterns-in-history "$hits/history-hits.txt" no_match "${st[1]}" "$hits/history-hits.txt"
  ls -ld "$HOME/.config/litellm" > "$hits/config-litellm.txt" 2>&1
  check secret-hygiene copilot-token-dir-in-repo "$hits/config-litellm.txt" config_dir_untouched
  local s
  collect_logs
  : > "$hits/evidence-leaks.txt"
  for s in "$(envval LITELLM_MASTER_KEY)" "$(envval SEARXNG_SECRET)" "$(envval POSTGRES_PASSWORD)" \
           "$(copilot_token)" $(cat "$REPO/.validate-keys" 2>/dev/null); do
    [[ -n "$s" ]] && grep -rlF "$s" "$EV" >> "$hits/evidence-leaks.txt"
  done
  check secret-hygiene evidence-is-redacted "$hits/evidence-leaks.txt" empty "$hits/evidence-leaks.txt"
}

cmd_drive() {
  init_out "$1"
  local feature="$2"
  case " $FEATURES " in *" $feature "*) ;; *) usage ;; esac
  [[ -d "$REPO" ]] || die "no instance under $OUT; run launch first"
  CUR="$feature"; mkdir -p "$EV/$CUR"
  "drive_$feature"
}

# collect_logs: copies the copy's process logs into evidence, redacted.
collect_logs() {
  local log
  mkdir -p "$EV/logs"
  for log in "$REPO"/logs/*.log; do
    [[ -f "$log" ]] && redact < "$log" > "$EV/logs/$(basename "$log")"
  done
}

cmd_cleanup() {
  init_out "$1"
  if [[ -d "$REPO" ]]; then
    mk stop > "$EV/cleanup-stop.txt" 2>&1
    wait_ports_free 60 || printf 'validate: ports still busy after stop\n' >&2
    collect_logs
    # make setup runs `direnv allow` when direnv exists; drop that grant with the copy.
    if command -v direnv >/dev/null 2>&1 && [[ -f "$REPO/.envrc" ]]; then
      direnv deny "$REPO/.envrc" >/dev/null 2>&1
    fi
    rm -rf "$REPO"
  fi
  # Prisma and npm downloads, about 300 MB.
  rm -rf "$OUT/cache"
  printf 'evidence: %s\nreport:   %s\n' "$EV" "$REPORT"
}

cmd_run() {
  # Not /tmp: it is RAM-backed tmpfs on many Linux hosts, and a run needs about 2 GB.
  init_out "${1:-${XDG_CACHE_HOME:-$HOME/.cache}/aiaiai-validate/$(date +%Y%m%d-%H%M%S)}"
  preflight
  trap 'cmd_cleanup "$OUT"' EXIT
  cmd_launch "$OUT"
  cmd_doctor "$OUT"
  local feature
  for feature in $FEATURES; do cmd_drive "$OUT" "$feature"; done
  local fails
  fails="$(grep -c $'\tFAIL\t' "$REPORT")"
  printf '\n%s failing checks\n' "$fails"
  [[ "$fails" -eq 0 ]]
}

case "${1:-}" in
  run)     cmd_run "${2:-}" ;;
  launch)  [[ $# -eq 2 ]] || usage; cmd_launch "$2" ;;
  doctor)  [[ $# -eq 2 ]] || usage; cmd_doctor "$2" ;;
  drive)   [[ $# -eq 3 ]] || usage; cmd_drive "$2" "$3" ;;
  cleanup) [[ $# -eq 2 ]] || usage; cmd_cleanup "$2" ;;
  *)       usage ;;
esac
