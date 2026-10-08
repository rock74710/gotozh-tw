#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
output_path=${1:-"$package_dir/build/Gotozh.app"}

case "$output_path" in
    /*) ;;
    *) output_path="$PWD/$output_path" ;;
esac

if [ -e "$output_path" ]; then
    echo "輸出路徑已存在：$output_path" >&2
    exit 1
fi

swift build --package-path "$package_dir" --configuration release --product GotozhMac
binary_dir=$(swift build --package-path "$package_dir" --configuration release --show-bin-path)
executable="$binary_dir/GotozhMac"
resource_bundle="$binary_dir/GotozhNative_GotozhCore.bundle"

if [ ! -x "$executable" ]; then
    echo "找不到已建置的 App 執行檔：$executable" >&2
    exit 1
fi
if [ ! -d "$resource_bundle" ]; then
    echo "找不到 SwiftPM 詞庫資源：$resource_bundle" >&2
    exit 1
fi

mkdir -p "$(dirname -- "$output_path")"
temporary_path=$(mktemp -d "${output_path}.tmp.XXXXXX")
report_temporary_path() {
    status=$?
    if [ "$status" -ne 0 ] && [ -d "$temporary_path" ]; then
        echo "打包失敗；暫存檔保留在：$temporary_path" >&2
    fi
}
trap report_temporary_path EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$temporary_path/Contents/MacOS" "$temporary_path/Contents/Resources"
cp "$executable" "$temporary_path/Contents/MacOS/GotozhMac"
ditto "$resource_bundle" "$temporary_path/Contents/Resources/GotozhNative_GotozhCore.bundle"
mkdir -p "$temporary_path/Contents/Resources/OpenCC-Licenses"
cp "$package_dir/Vendor/OpenCC/LICENSE" "$temporary_path/Contents/Resources/OpenCC-Licenses/OpenCC-LICENSE.txt"
cp "$package_dir/Vendor/OpenCC/DATA-LICENSE" "$temporary_path/Contents/Resources/OpenCC-Licenses/OpenCC-DATA-LICENSE.txt"
cp "$package_dir/Vendor/OpenCC/THIRD-PARTY-NOTICES.md" "$temporary_path/Contents/Resources/OpenCC-Licenses/THIRD-PARTY-NOTICES.txt"
cp "$package_dir/Vendor/OpenCC/deps/marisa-0.3.1/COPYING.md" "$temporary_path/Contents/Resources/OpenCC-Licenses/marisa-trie-LICENSE.txt"
cp "$package_dir/Vendor/OpenCC/deps/darts-clone-0.32h/COPYING.md" "$temporary_path/Contents/Resources/OpenCC-Licenses/darts-clone-LICENSE.txt"
cp "$package_dir/Vendor/OpenCC/deps/rapidjson-1.1.0/LICENSE" "$temporary_path/Contents/Resources/OpenCC-Licenses/RapidJSON-LICENSE.txt"
cat > "$temporary_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>GotozhMac</string>
    <key>CFBundleIdentifier</key>
    <string>tw.gotozh.native</string>
    <key>CFBundleName</key>
    <string>Gotozh</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
mv "$temporary_path" "$output_path"
trap - EXIT HUP INT TERM
echo "已建立本機測試用 App：$output_path"
