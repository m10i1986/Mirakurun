#!/bin/bash
#
# podman.sh - docker compose 相当の処理を podman コマンドで行うラッパースクリプト
#
# container/docker-compose.yml の設定を podman コマンドへ翻訳したものです。
# podman-compose は使用せず、素の podman コマンドのみで build / run / up / down 等を行います。
#
# 使い方:
#   ./container/podman.sh <command>
#
# command:
#   build      イメージをビルドする
#   setup      セットアップ用に一度だけ起動する (SETUP=true, --rm)
#   run        一度だけ起動する (--rm)
#   debug      デバッグモードで一度だけ起動する (DEBUG=true, --rm)
#   up         デタッチでコンテナを起動する (restart=always)
#   down       コンテナを停止・削除する
#   restart    コンテナを再起動する (down + up)
#   logs       コンテナのログを追従表示する
#   bash       起動中コンテナで bash を開く
#   rebuild    (build + down + up) を連続で行う
#
# 環境変数 (rootless 運用向け):
#   DEVICES         コンテナへ渡すデバイスを空白区切りで指定 (--device)
#                   例: DEVICES="/dev/dvb /dev/bus/usb"
#                   未指定ならデバイスを渡さない (デバイスの無い開発環境向け)
#   DISABLE_PCSCD   1 でコンテナ内 pcscd を起動せず、ホストの pcscd を共有する
#   PCSCD_COMM      共有する pcscd ソケットのパス (既定: /run/pcscd/pcscd.comm)
#   DEV_ALL_DEVICES 1 で /dev を丸ごと bind mount する (開発用フォールバック)
#
# rootless での前提 (実行環境):
#   - 実行ユーザを各デバイスの所有グループ (video, dialout 等) に追加しておく
#   - --group-add keep-groups でその補助グループをコンテナへ引き継ぐ
#   - /opt/mirakurun/volumes/* は実行ユーザ所有で作成しておく
#     (rootless ではコンテナ内 root = 実行ユーザにマップされる)
#
set -euo pipefail

# ---- パス解決 ----------------------------------------------------------------
# このスクリプトが置かれている container/ ディレクトリと、その親 (プロジェクトルート)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# ---- 設定値 (docker-compose.yml と対応) --------------------------------------
# image: chinachu/mirakurun:${MIRAKURUN_IMAGE_TAG:-latest}
IMAGE="localhost/chinachu/mirakurun:${MIRAKURUN_IMAGE_TAG:-latest}"
# container_name: mirakurun
CONTAINER="mirakurun"
# build.dockerfile: container/${DOCKERFILE:-Containerfile}
DOCKERFILE="${DOCKERFILE:-Containerfile}"

# ---- 共通 run オプションの組み立て -------------------------------------------
# docker-compose.yml の各設定を podman run のオプションへ変換します。
# 配列で組み立てることで、空白を含む値も安全に渡せます。
build_run_opts() {
  RUN_OPTS=(
    # container_name: mirakurun
    --name "${CONTAINER}"

    # network_mode: host
    # rootless でも 40772 (>1024) のため特権ポート不要で利用可
    --network host

    # cap_add
    # ※ rootless では userns 内でのみ有効。SYS_NICE はプロセス優先度の調整に使用
    --cap-add SYS_ADMIN
    --cap-add SYS_NICE

    # rootless でホスト側の補助グループ (video, dialout 等) をコンテナへ引き継ぎ、
    # チューナー/カードリーダー等のデバイスへアクセス可能にする (crun: keep_original_groups)
    # ※ device_cgroup_rules ('c *:* rmw') は cgroup v2 + rootless では委譲されず
    #    機能しないため廃止し、デバイスは下記 DEVICES で個別に渡す
    --group-add keep-groups

    # tmpfs: /tmp
    --tmpfs /tmp

    # logging: json-file (max-size 10m)
    # ※ docker の max-file は podman の json-file ドライバでは未対応のため max-size のみ
    --log-driver json-file
    --log-opt max-size=10m

    # environment
    --env "TZ=Asia/Tokyo"
    --env "DISABLE_PCSCD=${DISABLE_PCSCD:-0}"
    --env "DISABLE_B25_TEST=${DISABLE_B25_TEST:-0}"
    # network_mode: host に合わせて DOCKER_NETWORK=host
    --env "DOCKER_NETWORK=host"

    # volumes
    --volume "/opt/mirakurun/volumes/run:/var/run"
    --volume "/opt/mirakurun/volumes/opt:/opt"
    --volume "/opt/mirakurun/volumes/config:/app-config"
    --volume "/opt/mirakurun/volumes/data:/app-data"
  )

  # デバイス指定: DEVICES="/dev/dvb /dev/bus/usb" のように空白区切りで渡す
  # 未指定ならデバイスを渡さない (デバイスの無い開発環境でもそのまま起動できる)
  if [ -n "${DEVICES:-}" ]; then
    for dev in ${DEVICES}; do
      RUN_OPTS+=( --device "${dev}" )
    done
  fi

  # ホストの pcscd を共有する場合 (DISABLE_PCSCD=1)。ソケットが存在する時のみマウント
  if [ "${DISABLE_PCSCD:-0}" = "1" ]; then
    local pcscd_comm="${PCSCD_COMM:-/run/pcscd/pcscd.comm}"
    if [ -S "${pcscd_comm}" ]; then
      RUN_OPTS+=( --volume "${pcscd_comm}:/run/pcscd/pcscd.comm" )
    fi
  fi

  # 開発用フォールバック: /dev を丸ごと bind mount (DEV_ALL_DEVICES=1)
  if [ "${DEV_ALL_DEVICES:-0}" = "1" ]; then
    RUN_OPTS+=( --volume "/dev:/dev" )
  fi
}

# ---- サブコマンド ------------------------------------------------------------
cmd_build() {
  # build.context: ../ (= プロジェクトルート), dockerfile: container/Containerfile
  podman build \
    -t "${IMAGE}" \
    -f "${SCRIPT_DIR}/${DOCKERFILE}" \
    "${PROJECT_ROOT}"
}

cmd_up() {
  build_run_opts
  # restart: always + デタッチ起動
  podman run -d \
    --restart always \
    "${RUN_OPTS[@]}" \
    "${IMAGE}"
}

cmd_run() {
  build_run_opts
  # 一度だけ起動 (--rm)。対話操作のため -it を付与。
  podman run --rm -it \
    "${RUN_OPTS[@]}" \
    "${IMAGE}"
}

cmd_setup() {
  build_run_opts
  # SETUP=true を付けて一度だけ起動
  podman run --rm -it \
    --env "SETUP=true" \
    "${RUN_OPTS[@]}" \
    "${IMAGE}"
}

cmd_debug() {
  build_run_opts
  # DEBUG=true を付けて一度だけ起動
  podman run --rm -it \
    --env "DEBUG=true" \
    "${RUN_OPTS[@]}" \
    "${IMAGE}"
}

cmd_down() {
  # 停止・削除 (存在しなくてもエラーにしない)
  podman stop "${CONTAINER}" 2>/dev/null || true
  podman rm "${CONTAINER}" 2>/dev/null || true
}

cmd_restart() {
  cmd_down
  cmd_up
}

cmd_rebuild() {
  cmd_build
  cmd_restart
}

cmd_logs() {
  podman logs -f "${CONTAINER}"
}

cmd_bash() {
  podman exec -it "${CONTAINER}" bash
}

usage() {
  # 先頭のコメントブロック (set -euo の手前まで) をそのまま使い方として表示
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '/^set -euo/d; s/^# \{0,1\}//'
}

# ---- ディスパッチ ------------------------------------------------------------
main() {
  local sub="${1:-}"
  case "${sub}" in
    build) cmd_build ;;
    up)    cmd_up ;;
    run)   cmd_run ;;
    setup) cmd_setup ;;
    debug) cmd_debug ;;
    down)  cmd_down ;;
    restart) cmd_restart ;;
    logs)  cmd_logs ;;
    bash)  cmd_bash ;;
    rebuild) cmd_rebuild ;;
    ""|-h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "unknown command: ${sub}" >&2
      echo >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
