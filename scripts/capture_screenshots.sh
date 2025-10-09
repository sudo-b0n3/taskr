#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR=${1:-docs/screenshots}
SCHEME=${SCHEME:-taskr}
PROJECT=${PROJECT:-taskr.xcodeproj}
DESTINATION=${DESTINATION:-'platform=macOS'}

RESULT_TMP="$(mktemp -d)"
RESULT_BUNDLE="${RESULT_TMP}/TaskrScreenshots.xcresult"

echo "Running UI tests to capture screenshots..."
SCREENSHOT_CAPTURE=1 xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -destination "${DESTINATION}" \
  test \
  -resultBundlePath "${RESULT_BUNDLE}"

mkdir -p "${OUTPUT_DIR}"
rm -f "${OUTPUT_DIR}"/*.png

ATTACH_EXPORT_DIR="$(mktemp -d)"
xcrun xcresulttool export attachments --path "${RESULT_BUNDLE}" --output-path "${ATTACH_EXPORT_DIR}"

MANIFEST_PATH="${ATTACH_EXPORT_DIR}/manifest.json"
if [[ ! -f "${MANIFEST_PATH}" ]]; then
  echo "No attachments manifest found; screenshot export failed." >&2
  exit 1
fi

echo "Exporting screenshots to ${OUTPUT_DIR}"
python3 - <<'PY' "${MANIFEST_PATH}" "${ATTACH_EXPORT_DIR}" "${OUTPUT_DIR}"
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
    stem = suggested.split("_")[0]
    destination = output_dir / f"{stem}.png"
    source = attachments_dir / exported_name
    shutil.copyfile(source, destination)
    print(f"  • {destination}")
PY

rm -rf "${ATTACH_EXPORT_DIR}" "${RESULT_TMP}"

for image in "${OUTPUT_DIR}"/*.png; do
  [[ -f "${image}" ]] || continue
  width=$(sips -g pixelWidth "${image}" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  if [[ -n "${width}" && "${width}" -gt 1 ]]; then
    new_width=$(( width / 2 ))
    if [[ "${new_width}" -gt 0 ]]; then
      sips --resampleWidth "${new_width}" "${image}" >/dev/null
    fi
  fi
done

echo "Screenshot capture complete."
