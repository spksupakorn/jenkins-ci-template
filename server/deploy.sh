#!/usr/bin/env bash
# วางไว้บน server ที่ /opt/apps/mattersolv/deploy.sh (chmod +x) ต้องส่ง APP_DIR=<โฟลเดอร์ที่มี docker-compose.yml และ .env ของ service นั้น>
# ใช้งาน: deploy.sh <ENV_KEY> <TAG> <SERVICE>
#   เช่น  deploy.sh BACKEND_TAG 3f2a9c1b7d4e backend
#
# 1) แก้ค่า <ENV_KEY>=<TAG> ใน .env (สำรองไว้เป็น .env.bak)
# 2) docker compose pull + up -d เฉพาะ service นั้น
# 3) prune image ที่ไม่ถูกใช้
# ถ้า pull/up ล้มเหลว จะคืนค่า .env เดิมแล้ว up -d กลับเป็น tag เดิม

set -Eeuo pipefail

readonly APP_DIR="${APP_DIR:?set APP_DIR to the compose project dir}"
readonly ENV_FILE="${APP_DIR}/.env"
readonly BACKUP_FILE="${ENV_FILE}.bak"
readonly LOCK_FILE="${APP_DIR}/.deploy.lock"

die() { echo "Error: $*" >&2; exit 1; }

[[ $# -eq 3 ]] || die "usage: $0 <ENV_KEY> <TAG> <SERVICE>"
key="$1"; tag="$2"; service="$3"

# ตรวจรูปแบบ argument กันการ inject คำสั่ง/อักขระแปลก ๆ ผ่าน ssh
[[ "$key"     =~ ^[A-Z_][A-Z0-9_]*$ ]]              || die "invalid ENV_KEY: $key"
[[ "$tag"     =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || die "invalid TAG: $tag"
[[ "$service" =~ ^[a-z0-9][a-z0-9_-]*$ ]]           || die "invalid SERVICE: $service"

cd "$APP_DIR"
[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found"

# กัน backend/frontend deploy พร้อมกันแล้วแก้ .env ชนกัน
exec 9>"$LOCK_FILE"
flock -w 600 9 || die "another deploy is still running"

docker compose config --services | grep -qx "$service" \
  || die "service '$service' not found in compose project at $APP_DIR"

cp -p "$ENV_FILE" "$BACKUP_FILE"
old_tag="$(grep -E "^${key}=" "$ENV_FILE" | tail -n1 | cut -d= -f2- || true)"

rollback() {
  echo "Deploy failed — restoring .env (${key}=${old_tag:-<unset>})" >&2
  cp -p "$BACKUP_FILE" "$ENV_FILE"
  docker compose up -d "$service" || true
}
trap rollback ERR

if grep -qE "^${key}=" "$ENV_FILE"; then
  sed -i "s|^${key}=.*|${key}=${tag}|" "$ENV_FILE"
else
  printf '%s=%s\n' "$key" "$tag" >> "$ENV_FILE"
fi
echo "${key}: ${old_tag:-<unset>} -> ${tag}"

docker compose pull "$service"
docker compose up -d --wait --wait-timeout 120 "$service"

trap - ERR

# ลบ image ที่ไม่มี container ใช้และ build มาเกิน 3 วัน; ล้มเหลว (เช่น prune ซ้อนกัน) ไม่ทำให้ deploy ที่สำเร็จแล้วล้ม
docker image prune -af --filter "until=72h" || true

docker compose ps "$service"
echo "Deployed ${service} @ ${tag}"
