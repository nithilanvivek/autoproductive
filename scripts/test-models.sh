#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-tests.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/Automation.swift" \
  "$ROOT/AutoProductive/Models/WorkflowDefinition.swift" \
  "$ROOT/AutoProductive/Models/FeatureCatalog.swift" \
  "$ROOT/AutoProductive/Models/FeatureComponentSupport.swift" \
  "$ROOT/AutoProductive/Models/ClipboardTransform.swift" \
  "$ROOT/AutoProductive/Models/ScreenReferenceImage.swift" \
  "$ROOT/AutoProductive/Models/AutomationWizardPlan.swift" \
  "$ROOT/AutoProductive/Models/SequenceDefinition.swift" \
  "$ROOT/AutoProductive/Models/MenuBarPopupLayout.swift" \
  "$ROOT/AutoProductive/Models/FileBucketShortcutSettings.swift" \
  "$ROOT/AutoProductive/Models/TouchpadGesture.swift" \
  "$ROOT/AutoProductive/Models/AudioProcessOwnership.swift" \
  "$ROOT/AutoProductive/Models/MacroRecordingBuffer.swift" \
  "$ROOT/AutoProductive/Models/InputMonitoringSettings.swift" \
  "$ROOT/AutoProductive/Services/ShortcutAnalyzer.swift" \
  "$ROOT/AutoProductive/Services/KeyboardKeyLabel.swift" \
  "$ROOT/AutoProductive/Services/EditableTextPolicy.swift" \
  "$ROOT/Tests/main.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"
