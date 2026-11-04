#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  up)      docker build -t bank-node:lab . && sudo containerlab deploy -t BankTopology.clab.yml && scripts/provision.sh ;;
  verify)  tests/verify.sh ;;
  failure) tests/failure.sh ;;
  logs)    docker exec clab-bank-b-collector sh -c 'tail -n 20 /var/log/remote/*' ;;
  down)    sudo containerlab destroy -t BankTopology.clab.yml --cleanup ;;
  *) echo "usage: $0 up|verify|failure|logs|down"; exit 1 ;;
esac