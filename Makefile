# -------------------------
# Flutter / Dart tooling
# -------------------------

FLUTTER := flutter
DART := dart

LIB := lib
TEST := test

.PHONY: help fixer fixer-plugins format format-plugins analyze analyze-plugins metrics test tests-plugins

help:
	@echo "Available commands:"
	@echo "  make fixer   - format + analyze + metrics (cs-fixer + phpstan analogue)"
	@echo "  make fixer-plugins   - format + analyze all packages/"
	@echo "  make tests-plugins   - run flutter test for each package/"
	@echo "  make format  - dart format"
	@echo "  make analyze - flutter analyze"
	@echo "  make metrics - dart_code_metrics"
	@echo "  make test    - flutter test"

# -------------------------
# 🔥 Main target
# -------------------------

fixer: format analyze metrics
	@echo "✔ fixer completed successfully"

.PHONY: format-plugins analyze-plugins

PACKAGE_DIRS := $(shell find packages -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

fixer-plugins: format-plugins analyze-plugins
	@echo "✔ fixer-plugins completed successfully"

tests-plugins:
	@echo "🧪 Running flutter test for packages..."
	@for pkg in $(PACKAGE_DIRS); do \
	  echo "Testing $$pkg"; \
	  cd $$pkg && $(FLUTTER) test; \
	done

# -------------------------
# Formatting (dart format)
# -------------------------

format:
	@echo "🧹 Formatting Dart code..."
	cd app && $(DART) format $(LIB) $(TEST)

format-plugins:
	@echo "🧹 Formatting plugin Dart code..."
	@for pkg in $(PACKAGE_DIRS); do \
	  echo "Formatting $$pkg"; \
	  cd $$pkg && $(DART) format .; \
	done

# -------------------------
# Static analysis (flutter_lints)
# -------------------------

analyze:
	@echo "🔍 Running flutter analyze..."
	cd app && $(FLUTTER) analyze

analyze-plugins:
	@echo "🔍 Running flutter analyze for packages..."
	@for pkg in $(PACKAGE_DIRS); do \
	  echo "Analyzing $$pkg"; \
	  cd $$pkg && $(FLUTTER) analyze; \
	done

# -------------------------
# Deep static metrics (dart_code_metrics)
# -------------------------

metrics:
	@echo "⚠ dart_code_metrics is disabled (incompatible with flutter_riverpod ^3.2.1); skipping metrics."

# -------------------------
# Tests
# -------------------------

tests:
	@echo "🧪 Running tests..."
	cd app && $(FLUTTER) test
