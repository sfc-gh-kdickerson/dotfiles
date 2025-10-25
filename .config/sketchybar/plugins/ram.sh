#!/usr/bin/env bash

sum_macos_vm_stats() {
  grep -Eo '[0-9]+' |
    awk '{ a += $1 * 4096 } END { print a }'
}

stats="$(vm_stat)"

used_and_cached=$( echo "$stats" | grep -E "(Pages active|Pages inactive|Pages speculative|Pages wired down|Pages occupied by compressor)" | sum_macos_vm_stats)
cached=$( echo "$stats" | grep -E "(Pages purgeable|File-backed pages)" | sum_macos_vm_stats)
free=$( echo "$stats" | grep -E "(Pages free)" | sum_macos_vm_stats)
used=$((used_and_cached - cached))
total=$((used_and_cached + free))

percent_used=$(echo "$used $total" | awk -v format="%3.1f%%" '{printf(format, 100*$1/$2)}')

percent_numeric=$(echo "$percent_used" | awk '{print int($1)}')
if (( percent_numeric < 50 )); then
  icon="=" 
elif (( percent_numeric < 75 )); then
  icon="≡" 
else
  icon="≣" 
fi

sketchybar --set "$NAME" icon="$icon" label="$percent_used"
