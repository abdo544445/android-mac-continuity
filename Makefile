.PHONY: all build-macos test-macos test-android test-e2e run-companion run-cli run-relay clean help

all: build-macos test-macos test-android test-e2e

build-macos:
	@echo "🔨 Building macOS Companion and CLI..."
	cd apps/macos && swift build --target ContinuityCompanion
	cd apps/macos && swift build --target ContinuityCLI

test-macos:
	@echo "🧪 Running Swift Protocol Automated Tests..."
	cd apps/macos && swift run ContinuityCLI test

test-android:
	@echo "🤖 Running Android Unit & Logic Test Suite..."
	python3 tests/android/run_android_tests.py

test-e2e:
	@echo "🚀 Running End-to-End Integration Tests..."
	python3 tests/integration/run_e2e_test.py

run-companion:
	@echo "💻 Launching Continuity Companion macOS App..."
	cd apps/macos && swift run ContinuityCompanion

run-cli:
	@echo "🖥️ Launching Continuity CLI..."
	cd apps/macos && swift run ContinuityCLI status

run-relay:
	@echo "📡 Launching E2E Encrypted Relay Server..."
	python3 services/optional-relay/relay_server.py

clean:
	@echo "🧹 Cleaning build artifacts..."
	rm -rf apps/macos/.build

help:
	@echo "Continuity Ecosystem Build System"
	@echo "Targets:"
	@echo "  make all           - Build macOS app & run all test suites"
	@echo "  make build-macos   - Build Swift companion and CLI"
	@echo "  make test-macos    - Run Swift protocol tests"
	@echo "  make test-e2e      - Run Python end-to-end integration tests"
	@echo "  make run-companion - Run SwiftUI macOS application"
	@echo "  make run-relay     - Start optional E2E encrypted relay server"
