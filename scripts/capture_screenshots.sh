#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR=${1:-docs/screenshots}
SCHEME=${SCHEME:-taskr}
PROJECT=${PROJECT:-taskr.xcodeproj}
DESTINATION=${DESTINATION:-'platform=macOS'}
THEMES_RAW=${THEMES:-"system catppuccinMocha tokyoNight gruvboxLight"}
AUTOMATION_CONFIG_PATH=${AUTOMATION_CONFIG_PATH:-"$HOME/Library/Containers/com.bone.taskr/Data/tmp/taskr_screenshot_config.json"}
AUTOMATION_RUNNER_CONFIG_PATH=${AUTOMATION_RUNNER_CONFIG_PATH:-"$HOME/Library/Containers/com.bone.taskrUITests.xctrunner/Data/Library/Containers/com.bone.taskr/Data/tmp/taskr_screenshot_config.json"}

read -r -a THEMES <<< "${THEMES_RAW}"
if [[ "${#THEMES[@]}" -eq 0 ]]; then
  THEMES=(system)
fi

echo "Capturing screenshots for themes: ${THEMES[*]}"

cleanup_tmp() {
  [[ -d "${1:-}" ]] && rm -rf "${1}"
}

write_automation_config() {
  local theme_value="${1}"
  python3 - "$theme_value" "${AUTOMATION_CONFIG_PATH}" "${AUTOMATION_RUNNER_CONFIG_PATH}" <<'PY'
import json
import pathlib
import sys

theme = sys.argv[1]
paths = [pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])]
payload = {
    "capture": True,
    "theme": theme,
}
payload_json = json.dumps(payload)
for path in paths:
    if not path:
        continue
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(payload_json, encoding="utf-8")
PY
}

clear_automation_config() {
  rm -f "${AUTOMATION_RUNNER_CONFIG_PATH}"
  rm -f "${AUTOMATION_CONFIG_PATH}"
}

trap clear_automation_config EXIT

clear_automation_config

for theme in "${THEMES[@]}"; do
  echo ""
  echo "=== Theme: ${theme} ==="

  write_automation_config "${theme}"

  RESULT_TMP="$(mktemp -d)"
  RESULT_BUNDLE="${RESULT_TMP}/TaskrScreenshots_${theme}.xcresult"

  echo "Running UI tests to capture screenshots..."
  SCREENSHOT_THEME="${theme}" SCREENSHOT_CAPTURE=1 xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "${DESTINATION}" \
    test \
    -resultBundlePath "${RESULT_BUNDLE}"

  THEME_OUTPUT_DIR="${OUTPUT_DIR}/${theme}"
  mkdir -p "${THEME_OUTPUT_DIR}"
  rm -f "${THEME_OUTPUT_DIR}"/*.png

  ATTACH_EXPORT_DIR="$(mktemp -d)"
  xcrun xcresulttool export attachments --path "${RESULT_BUNDLE}" --output-path "${ATTACH_EXPORT_DIR}"

  MANIFEST_PATH="${ATTACH_EXPORT_DIR}/manifest.json"
  if [[ ! -f "${MANIFEST_PATH}" ]]; then
    echo "No attachments manifest found; screenshot export failed." >&2
    cleanup_tmp "${ATTACH_EXPORT_DIR}"
    cleanup_tmp "${RESULT_TMP}"
    exit 1
  fi

  echo "Exporting screenshots to ${THEME_OUTPUT_DIR}"
  python3 - <<'PY' "${MANIFEST_PATH}" "${ATTACH_EXPORT_DIR}" "${THEME_OUTPUT_DIR}"
import json
import shutil
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
attachments_dir = Path(sys.argv[2])
output_dir = Path(sys.argv[3])

with manifest_path.open("r", encoding="utf-8") as handle:
    manifest = json.load(handle)

records = []
for group in manifest:
    for entry in group.get("attachments", []):
        records.append(entry)

if not records:
    raise SystemExit("No screenshot attachments found in result bundle.")

records.sort(key=lambda item: item.get("suggestedHumanReadableName", ""))

for record in records:
    exported_name = record["exportedFileName"]
    suggested = record.get("suggestedHumanReadableName", exported_name)
    stem = suggested.replace(" ", "-")
    if stem.lower().endswith(".png"):
        stem = stem[:-4]
    destination = output_dir / f"{stem}.png"
    source = attachments_dir / exported_name
    shutil.copyfile(source, destination)
    print(f"  • {destination}")
PY

  cleanup_tmp "${ATTACH_EXPORT_DIR}"
  cleanup_tmp "${RESULT_TMP}"

  for image in "${THEME_OUTPUT_DIR}"/*.png; do
    [[ -f "${image}" ]] || continue
    width=$(sips -g pixelWidth "${image}" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    if [[ -n "${width}" && "${width}" -gt 1 ]]; then
      new_width=$(( width / 2 ))
      if [[ "${new_width}" -gt 0 ]]; then
        sips --resampleWidth "${new_width}" "${image}" >/dev/null
      fi
    fi
  done
done

echo ""
echo "Screenshot capture complete."
