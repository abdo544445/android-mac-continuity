.PHONY: all build-macos build-android install-android test-macos test-android test-e2e run-companion open-mac reveal run-cli run-relay clean help

all: build-macos build-android test-macos test-android test-e2e

build-macos:
	@echo "🔨 Building macOS Companion .app bundle and CLI..."
	./scripts/bundle_macos_app.sh

build-android:
	@echo "🤖 Building Android Debug APK..."
	cd apps/android && JAVA_HOME=~/.jdk21/Contents/Home ./gradlew assembleDebug
	@mkdir -p dist
	@cp apps/android/app/build/outputs/apk/debug/app-debug.apk dist/app-debug.apk
	@echo "✅ Android APK copied to dist/app-debug.apk"

install-android:
	@echo "📲 Installing Continuity APK on connected Android device via ADB..."
	/opt/homebrew/bin/adb install -r dist/app-debug.apk

open-mac:
	@echo "🚀 Launching Continuity Companion .app..."
	open dist/ContinuityCompanion.app

reveal:
	@echo "📂 Opening Finder at distribution directory..."
	open dist

run-companion:
	@echo "💻 Launching Continuity Companion macOS App..."
	open dist/ContinuityCompanion.app

run-cli:
	@echo "🖥️ Launching Continuity CLI..."
	dist/ContinuityCLI status

test-macos:
	@echo "🧪 Running Swift Protocol Automated Tests..."
	cd apps/macos && swift run ContinuityCLI test

test-android:
	@echo "🤖 Running Android Unit & Logic Test Suite..."
	python3 tests/android/run_android_tests.py

test-e2e:
	@echo "🚀 Running End-to-End Integration Tests..."
	python3 tests/integration/run_e2e_test.py

run-relay:
	@echo "📡 Launching E2E Encrypted Relay Server..."
	python3 services/optional-relay/relay_server.py

clean:
	@echo "🧹 Cleaning build artifacts..."
	rm -rf apps/macos/.build dist

help:
	@echo "Continuity Ecosystem Build System"
	@echo "Targets:"
	@echo "  make all           - Build macOS .app, Android APK & run all test suites"
	@echo "  make build-macos   - Build macOS ContinuityCompanion.app bundle"
	@echo "  make build-android - Build Android APK"
	@echo "  make open-mac      - Launch ContinuityCompanion.app in macOS GUI"
	@echo "  make reveal        - Open dist/ directory in Finder"
	@echo "  make install-android - Install APK to phone via ADB"
	@echo "  make test-macos    - Run Swift protocol tests"
	@echo "  make test-android  - Run Android logic tests"
	@echo "  make test-e2e      - Run Python end-to-end integration tests"
