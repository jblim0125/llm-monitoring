#!/usr/bin/env bash
# docker-compose 스택 정리
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT/docker-compose"

PURGE="${1:-}"
if [[ "$PURGE" == "--purge" || "$PURGE" == "-v" ]]; then
  echo "[!] 볼륨까지 삭제합니다 (모든 모니터링 데이터 손실)."
  docker compose down -v
else
  echo "[+] 컨테이너만 정리합니다. (데이터 유지)"
  echo "    데이터까지 지우려면:  $0 --purge"
  docker compose down
fi
