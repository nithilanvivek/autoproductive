#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-execution-tests.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -O -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeatureComponentSupport.swift" \
  "$ROOT/AutoProductive/Models/Automation.swift" \
  "$ROOT/AutoProductive/Models/WorkflowDefinition.swift" \
  "$ROOT/AutoProductive/Models/FeatureCatalog.swift" \
  "$ROOT/AutoProductive/Models/ClipboardTransform.swift" \
  "$ROOT/AutoProductive/Models/FeaturePackageManifest.swift" \
  "$ROOT/AutoProductive/Models/FeatureSelectionState.swift" \
  "$ROOT/AutoProductive/Models/FeatureInputPlan.swift" \
  "$ROOT/AutoProductive/Models/ScreenReferenceImage.swift" \
  "$ROOT/AutoProductive/Models/ReportDiagnostics.swift" \
  "$ROOT/AutoProductive/Models/ProblemReport.swift" \
  "$ROOT/AutoProductive/Services/WorkflowEngine.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageStore.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageDownloader.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageRepository.swift" \
  "$ROOT/AutoProductive/Services/FeaturePackageGenerations.swift" \
  "$ROOT/AutoProductive/Services/FeatureComponentRunner.swift" \
  "$ROOT/AutoProductive/Services/FeatureComponentDispatcher.swift" \
  "$ROOT/AutoProductive/Services/FeatureInputPlayer.swift" \
  "$ROOT/AutoProductive/Services/SystemControlService.swift" \
  "$ROOT/AutoProductive/Services/DesktopAutomationService.swift" \
  "$ROOT/AutoProductive/Services/DockWindowCapture.swift" \
  "$ROOT/AutoProductive/Services/DockWindowMatching.swift" \
  "$ROOT/AutoProductive/Services/DockAccessibilityReader.swift" \
  "$ROOT/AutoProductive/Services/DockSpaceNavigation.swift" \
  "$ROOT/AutoProductive/Services/ImageMatcher.swift" \
  "$ROOT/AutoProductive/Services/ScaledImageMatcher.swift" \
  "$ROOT/Tests/ExecutionTests.swift" -o "$TEST_DIR/tests" \
  -framework AppKit -framework ScreenCaptureKit
AUTOPRODUCTIVE_DIAGNOSTICS_DIR="$TEST_DIR/diagnostics" "$TEST_DIR/tests"
