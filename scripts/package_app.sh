#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MeetHelp"
APP_IDENTIFIER="com.bhanuprakash.MeetHelp"
PROJECT="$APP_NAME.xcodeproj"
SCHEME="$APP_NAME"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-.xcodebuild}"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
SOURCE_APP="$PRODUCTS_DIR/$APP_NAME.app"
OUTPUT_APP="$APP_NAME.app"
OUTPUT_ZIP="$APP_NAME.zip"
ENTITLEMENTS="$APP_NAME/Resources/$APP_NAME.entitlements"

if [[ ! -d "$PROJECT" ]]; then
  echo "error: $PROJECT not found. Run this script from the repository root." >&2
  exit 1
fi

if [[ -d /Applications/Xcode.app && -z "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required to package $APP_NAME.app." >&2
  exit 1
fi

echo "Building $SCHEME ($CONFIGURATION) with Xcode..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  build

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "error: expected app product was not created at $SOURCE_APP" >&2
  exit 1
fi

echo "Copying app product to $OUTPUT_APP..."
rm -rf "$OUTPUT_APP"
ditto "$SOURCE_APP" "$OUTPUT_APP"

if [[ -f .env ]]; then
  echo "Bundling .env into app resources..."
  mkdir -p "$OUTPUT_APP/Contents/Resources"
  cp .env "$OUTPUT_APP/Contents/Resources/.env"
fi

echo "Signing $OUTPUT_APP..."
codesign --force --deep --sign - \
  --entitlements "$ENTITLEMENTS" \
  --requirements "=designated => identifier \"$APP_IDENTIFIER\"" \
  "$OUTPUT_APP"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"

echo "Creating $OUTPUT_ZIP..."
rm -f "$OUTPUT_ZIP"
ditto -c -k --keepParent "$OUTPUT_APP" "$OUTPUT_ZIP"

echo "Packaged $OUTPUT_APP and $OUTPUT_ZIP"
