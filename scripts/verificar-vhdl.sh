#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
rtl="$root/rtl"

ghdl -a --std=08 "$rtl"/{def_package,Adder_INT,Multiplier_INT,DPU_TOP_INT,TC_INT_top,tcu_wrapper}.vhd
cp "$root"/sim/*_patterns.txt .
for bench in tb_tcu_int_pipeline tb_tcu_wrapper_xbus tb_tcu_wrapper_protecciones; do
  ghdl -a --std=08 "$root/sim/$bench.vhd"
  ghdl -e --std=08 "$bench"
  if ! ghdl -r --std=08 "$bench" --assert-level=error --stop-time=5ms > "$bench.log" 2>&1 ||
     ! grep 'VALIDACION .*: EXITOSA' "$bench.log"; then
    cat "$bench.log"
    exit 1
  fi
done

if [[ -n ${NEORV32_HOME:-} ]]; then
  sources=()
  while IFS= read -r source || [[ -n "$source" ]]; do
    [[ "$source" == '$NEORV32_HOME/'* ]] || continue
    sources+=("$NEORV32_HOME/${source#\$NEORV32_HOME/}")
  done < "$NEORV32_HOME/rtl/file_list_core.f"
  ghdl -a --std=08 --work=neorv32 "${sources[@]}"
  ghdl -a --std=08 "$rtl/neorv32_tcu_top.vhd"
  ghdl -e --std=08 neorv32_tcu_top
  printf '%s\n' 'Integración NEORV32 elaborada'
fi
