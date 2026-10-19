#!/usr/bin/env bash
# Existing-server upgrade for release __RELEASE_ID__.
#   sudo bash upgrade-server.sh --check    # read-only validation; prints what would happen
#   sudo bash upgrade-server.sh --apply    # backup -> build/load API image -> migrate -> publish web
#
# Safety rules:
#   * Existing server .env, database container and planner-db volume are retained.
#   * Database is dumped with pg_dump and verified before anything is published.
#   * API image / compose file / frontend are backed up; failures restore them automatically.
#   * SQL migrations are additive and are never rolled back by this script.
#
# Optional overrides:
#   WEB_ROOT=/path/to/nginx/root     when auto-detection finds several candidate roots
#   IMAGE_ARCHIVE=/tmp/api-image.tar.gz   pre-built API image tar (docker load fallback)
set -Eeuo pipefail
umask 077

mode=${1:---check}
release_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
project_dir=${PROJECT_DIR:-/opt/sjtu-study-planner}
release_id=__RELEASE_ID__
api_origin=__API_ORIGIN__
release_image=study-planner-api:$release_id
env_file=$project_dir/apps/api/.env
compose_file=$project_dir/apps/api/docker-compose.server.yml
source_dir=$release_dir/source
release_web=$release_dir/web
backup_dir=$project_dir/backups/$release_id-$(date +%Y%m%d-%H%M%S)
api_changed=0
web_moved=0
api_host=${api_origin#https://}; api_host=${api_host%%/*}
web_root=""

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ $mode == --check || $mode == --apply ]] || die "Use --check or --apply."
[[ $EUID -eq 0 ]] || die "Run with sudo: sudo bash upgrade-server.sh $mode"
case "$release_dir" in
  "$project_dir/releases/"*) ;;
  *) die "Extract this release below $project_dir/releases/ first (for example: $project_dir/releases/$release_id)." ;;
esac
for tool in docker nginx curl python3 awk sed; do
  command -v "$tool" >/dev/null || die "Missing command: $tool"
done
[[ -f $release_dir/DEPLOY.md ]] || die "Release is incomplete: DEPLOY.md missing."
[[ -f $release_dir/release.json ]] || die "Release is incomplete: release.json missing."
[[ -f $source_dir/apps/api/Dockerfile ]] || die "Release source is incomplete: Dockerfile missing."
[[ -f $source_dir/apps/api/db/migrations/202610200001_learning_relations_capacity.sql ]] || die "Release source is missing the learning-relations migration."
[[ -f $source_dir/apps/api/db/migrations/202610220001_account_deletion.sql ]] || die "Release source is missing the account-deletion migration."
[[ -f $release_web/index.html && -f $release_web/main.dart.js ]] || die "Release frontend is incomplete (index.html / main.dart.js)."
[[ -f $env_file ]] || die "Existing server .env was not found: $env_file. Nothing was changed."
[[ -f $compose_file ]] || die "Existing Compose file was not found: $compose_file. Nothing was changed."

say "Release:        $release_id"
say "Release source: $release_dir"
say "Project:        $project_dir"
say "API origin:     $api_origin"

# ---------------------------------------------------------------------------
# 1. Validate the existing deployment and the release content (read-only).
# ---------------------------------------------------------------------------
old_compose=(docker compose --env-file "$env_file" -f "$compose_file")
"${old_compose[@]}" config --quiet
api_id=$("${old_compose[@]}" ps -q api)
db_id=$("${old_compose[@]}" ps -q db)
[[ -n $api_id && -n $db_id ]] || die "Existing api/db containers were not found. Do not start a new database; restore the previous deployment first."
project_name=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$api_id")
[[ -n $project_name && $project_name != '<no value>' ]] || die "Cannot identify the existing Compose project."
[[ $(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$db_id") == "$project_name" ]] || die "API and database belong to different Compose projects."
old_image=$(docker inspect --format '{{.Image}}' "$api_id")
compose=(docker compose --project-name "$project_name" --env-file "$env_file" -f "$compose_file")
new_compose=(docker compose --project-name "$project_name" --env-file "$env_file" -f "$source_dir/apps/api/docker-compose.server.yml")
"${new_compose[@]}" config --quiet
say "Compose project: $project_name"
say "Database ID:     $db_id"

nginx -t >/dev/null
nginx -T 2>/dev/null | python3 -c 'import sys,re; text=sys.stdin.read(); sys.exit(0 if re.search(r"application/wasm\s+[^;]*\bwasm\b", text) else "Flutter requires application/wasm in the Nginx MIME configuration; fix it before publishing (see DEPLOY.md).")' || die "Nginx is missing the Flutter WASM MIME type; run the Nginx repair documented in DEPLOY.md first."
nginx -T 2>/dev/null | python3 -c 'import sys; text=sys.stdin.read(); sys.exit(0 if "/api/" in text and "127.0.0.1:8787" in text else "Nginx must proxy /api/ to 127.0.0.1:8787.")' >/dev/null || say "WARN: could not confirm an /api/ proxy to 127.0.0.1:8787 in nginx -T output; verify manually."

if [[ -n ${WEB_ROOT:-} ]]; then
  web_root=$WEB_ROOT
else
  mapfile -t roots < <(nginx -T 2>/dev/null | sed -n 's/^[[:space:]]*root[[:space:]]\+\([^;]*\);.*/\1/p' | sort -u)
  candidates=()
  for candidate in "${roots[@]}"; do
    candidate=${candidate%\"}; candidate=${candidate#\"}; candidate=${candidate%\'}; candidate=${candidate#\'}
    case "$candidate" in
      "$project_dir"/*) candidates+=("$candidate") ;;
    esac
  done
  if (( ${#candidates[@]} == 0 )); then
    die "No Nginx root under $project_dir was found. Set WEB_ROOT=/path/to/current/web-root and rerun."
  elif (( ${#candidates[@]} == 1 )); then
    web_root=${candidates[0]}
  else
    live=()
    for candidate in "${candidates[@]}"; do
      [[ -f "$candidate/index.html" && -f "$candidate/main.dart.js" ]] && live+=("$candidate")
    done
    if (( ${#live[@]} == 1 )); then
      web_root=${live[0]}
    else
      printf 'Candidate Nginx roots under %s:\n' "$project_dir" >&2
      printf '  %s\n' "${candidates[@]}" >&2
      die "Several candidate web roots found. Re-run with WEB_ROOT=/path/to/current/web-root."
    fi
  fi
fi
[[ -d $web_root ]] || die "Configured web root does not exist: $web_root"
[[ -f $web_root/index.html ]] || die "Configured web root has no index.html: $web_root"
[[ -f $web_root/main.dart.js ]] || die "Configured web root has no main.dart.js: $web_root"
say "Nginx web root: $web_root"

python3 - "$env_file" "$release_web/main.dart.js" "$api_origin" <<'PY'
from pathlib import Path
import sys
rows = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.strip() and not line.lstrip().startswith('#') and '=' in line:
        key, value = line.split('=', 1)
        rows[key.strip()] = value.strip().strip('"').strip("'")
required = ['POSTGRES_PASSWORD', 'DATABASE_URL', 'JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET']
missing = [key for key in required if not rows.get(key)]
if missing:
    raise SystemExit('Existing server configuration is incomplete: ' + ', '.join(missing) + '. Values were not printed.')
from urllib.parse import urlparse
database = urlparse(rows.get('DATABASE_URL', ''))
if database.hostname in ('127.0.0.1', 'localhost'):
    raise SystemExit('DATABASE_URL points to ' + database.hostname + '; inside Docker it must use the compose service hostname "db". Fix apps/api/.env on the server first.')
smtp_missing = [key for key in ('SMTP_USER', 'SMTP_PASS') if not rows.get(key)]
if smtp_missing:
    print('WARNING: ' + ', '.join(smtp_missing) + ' is empty in ' + sys.argv[1] + '; registration verification emails will return 503 until filled on the server (the release package never contains SMTP secrets).', file=sys.stderr)
origins = [item.strip() for item in rows.get('WEB_ORIGIN', '').split(',') if item.strip()]
if sys.argv[3] not in origins:
    raise SystemExit('WEB_ORIGIN must contain ' + sys.argv[3] + '. Current value was not printed.')
if sys.argv[3].encode() not in Path(sys.argv[2]).read_bytes():
    raise SystemExit('Frontend bundle was not built for ' + sys.argv[3] + '; rebuild the Web client.')
print('Server configuration verified (required secrets present, WEB_ORIGIN and frontend origin match). Secrets were not printed.')
PY

curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8787/api/health >/dev/null
"${compose[@]}" exec -T db pg_isready -U planner -d planner >/dev/null
say "Existing API health and database availability verified."

# Image plan: reuse an already-loaded release image, load an uploaded image tar, or build here.
image_ready=0
if docker image inspect "$release_image" >/dev/null 2>&1; then
  image_ready=1
  say "API image: $release_image is already loaded."
fi
if (( image_ready == 0 )); then
  image_candidates=()
  [[ -n ${IMAGE_ARCHIVE:-} && -f ${IMAGE_ARCHIVE:-} ]] && image_candidates+=("$IMAGE_ARCHIVE")
  while IFS= read -r file; do image_candidates+=("$file"); done < <(find "$release_dir" -maxdepth 1 \( -name "api-image*.tar.gz" -o -name "study-planner-api-*.tar.gz" \) 2>/dev/null)
  if (( ${#image_candidates[@]} > 0 )) && [[ $mode == --apply ]]; then
    say "Loading API image from ${image_candidates[0]} ..."
    docker load < "${image_candidates[0]}"
    docker image inspect "$release_image" >/dev/null 2>&1 || die "Loaded image tar does not contain $release_image."
    image_ready=1
  fi
fi
if (( image_ready == 0 )); then
  base_ready=0
  docker image inspect node:22-bookworm-slim >/dev/null 2>&1 && base_ready=1
  npm_code=$(curl -s --max-time 8 -o /dev/null -w '%{http_code}' https://registry.npmjs.org/ 2>/dev/null || true)
  docker_code=$(curl -s --max-time 8 -o /dev/null -w '%{http_code}' https://registry-1.docker.io/v2/ 2>/dev/null || true)
  say "API image $release_image is NOT loaded yet."
  say "Node base image present locally: $base_ready"
  say "Network probe: registry.npmjs.org=$npm_code registry-1.docker.io=$docker_code"
  if (( base_ready == 1 )) && [[ $npm_code == 2* ]]; then
    say "Server looks able to build the API image locally (--apply will run docker build)."
  else
    say "Server may not be able to build the image (offline or missing base image)."
    say "Recommended: upload the prebuilt image tar, then run: docker load < /tmp/study-planner-api-$release_id-image.tar.gz"
    say "Alternatively place it in $release_dir/ as api-image.tar.gz; --apply will load it automatically."
  fi
fi

df -h "$project_dir" | tail -n +2 | sed 's/^/Disk: /'
if [[ $mode == --check ]]; then
  say ""
  say "CHECK COMPLETE: no files, containers, images or database records were changed."
  say "To publish: sudo bash $release_dir/upgrade-server.sh --apply"
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Apply. Any failure restores the previous API image, Compose file and frontend.
# ---------------------------------------------------------------------------
rollback() {
  result=$?
  trap - ERR
  set +e
  printf '\nUPGRADE FAILED: restoring the previous API image, Compose file and frontend.\nDatabase migrations are additive and are retained.\n' >&2
  if [[ $web_moved == 1 ]]; then
    if [[ -e $web_root || -L $web_root ]]; then mv -- "$web_root" "$backup_dir/failed-web"; fi
    if [[ -d $backup_dir/web ]]; then mv -- "$backup_dir/web" "$web_root"; fi
  fi
  if [[ $api_changed == 1 ]]; then
    if [[ -f $backup_dir/docker-compose.server.yml ]]; then cp -p -- "$backup_dir/docker-compose.server.yml" "$compose_file"; fi
    docker tag "$old_image" study-planner-api:latest >/dev/null 2>&1
    "${compose[@]}" up -d --no-deps --force-recreate --wait --wait-timeout 180 api >/dev/null 2>&1
  fi
  nginx -t >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1
  printf 'Backup retained at %s. No database restore or data deletion was performed.\n' "$backup_dir" >&2
  exit "$result"
}
mkdir -p -- "$project_dir/backups"
mkdir -- "$backup_dir"
chmod 700 -- "$backup_dir"
trap rollback ERR

cp -p -- "$env_file" "$backup_dir/server.env"
chmod 600 -- "$backup_dir/server.env"
cp -p -- "$compose_file" "$backup_dir/docker-compose.server.yml"
docker tag "$old_image" "study-planner-api:before-$release_id-$(date +%Y%m%d-%H%M%S)"
printf '%s\n' "$old_image" > "$backup_dir/previous-image-id.txt"
"${compose[@]}" exec -T db pg_dump -U planner -d planner -Fc > "$backup_dir/planner.dump"
[[ -s $backup_dir/planner.dump ]] || die "Database backup is empty. Publishing was not started."
"${compose[@]}" exec -T db pg_restore --list < "$backup_dir/planner.dump" > "$backup_dir/backup-contents.txt"
say "Database backup verified: $backup_dir/planner.dump"

cp -a -- "$web_root" "$backup_dir/web"
say "Previous frontend backed up to $backup_dir/web"

if (( image_ready == 0 )); then
  say "Building API image from the release source (requires Docker Hub + npm registry access) ..."
  if ! docker build -f "$source_dir/apps/api/Dockerfile" -t "$release_image" "$source_dir"; then
    die "docker build failed. Upload the prebuilt image tar, run 'docker load < /tmp/study-planner-api-$release_id-image.tar.gz', then rerun --apply."
  fi
fi
"${new_compose[@]}" config --quiet
api_changed=1
cp -p -- "$source_dir/apps/api/docker-compose.server.yml" "$compose_file"
docker tag "$release_image" study-planner-api:latest
say "Recreating the API container (migrations run automatically at startup) ..."
"${compose[@]}" up -d --no-deps --force-recreate --wait --wait-timeout 180 api

health_ok=0
for _ in $(seq 1 30); do
  if curl --fail --silent --show-error --max-time 5 http://127.0.0.1:8787/api/health >/dev/null 2>&1; then health_ok=1; break; fi
  sleep 2
done
(( health_ok == 1 )) || die "API health check did not pass after the upgrade."
say "API health check passed."

migration_ok=0
for _ in $(seq 1 30); do
  applied=$("${compose[@]}" exec -T db psql -U planner -d planner -Atc \
    "select count(*) from schema_migrations where name='202610220001_account_deletion.sql'" 2>/dev/null | tr -d '[:space:]' || true)
  if [[ $applied == 1 ]]; then migration_ok=1; break; fi
  sleep 2
done
(( migration_ok == 1 )) || die "New migration 202610220001_account_deletion.sql was not recorded by the API."
say "New database migration applied: 202610220001_account_deletion.sql"
[[ $("${compose[@]}" ps -q db) == "$db_id" ]] || die "Database container identity unexpectedly changed."
say "Database container was retained (no volume change)."

web_moved=1
printf '%s\n' "$web_root" > "$backup_dir/web-root.txt"
mv -- "$web_root" "$backup_dir/web-live"
mkdir -p -- "$(dirname "$web_root")"
cp -a -- "$release_web" "$web_root"
chmod -R a+rX -- "$web_root"
[[ -f $web_root/index.html && -f $web_root/main.dart.js && -f $web_root/canvaskit/chromium/canvaskit.wasm ]] || die "Published frontend is incomplete."
nginx -t
nginx -s reload
say "Frontend published to $web_root and Nginx reloaded."

wasm_headers=$(curl --fail --silent --show-error --head --max-time 20 --resolve "$api_host:443:127.0.0.1" "$api_origin/canvaskit/chromium/canvaskit.wasm")
[[ ${wasm_headers,,} == *'content-type: application/wasm'* ]] || die "Published WASM has an incorrect MIME type; check Nginx."
say "WASM MIME type verified."
curl --fail --silent --show-error --max-time 20 --resolve "$api_host:443:127.0.0.1" "$api_origin/api/health" >/dev/null
say "HTTPS API health verified."
if curl --fail --silent --show-error --head --max-time 20 -H 'Accept-Encoding: gzip' --resolve "$api_host:443:127.0.0.1" "$api_origin/main.dart.js" | grep -qi '^content-encoding:.*gzip'; then
  say "JavaScript gzip verified."
else
  say "WARN: main.dart.js was not served with Content-Encoding: gzip; the site still works but first load will be slower."
fi

trap - ERR
say ""
say "UPGRADE COMPLETE: $api_origin/"
say "API image:      $release_image (study-planner-api:latest)"
say "Release source: $release_dir/source"
say "Backup:         $backup_dir"
say ""
say "Next steps:"
say "  1. Hard-refresh the site (Ctrl+F5) and log in with an existing server account."
say "  2. Verify the existing plan, full-cycle calendar, capacity editor and the three study entries."
say "  3. Do not clear browser site storage; local IndexedDB/Sembast data will sync normally."
say "  4. Upgrade/reinstall desktop clients soon: old clients receive an explicit 426 upgrade prompt when the cloud already contains temporary-learning/extra-study logs."
say "  5. Rollback: see DEPLOY.md (API image + frontend revert; database migrations are retained)."
