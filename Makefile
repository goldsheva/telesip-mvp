# -------------------------
# Flutter / Dart tooling
# -------------------------

FLUTTER := flutter
DART := dart

LIB := lib
TEST := test

.PHONY: help fixer format analyze metrics test

help:
	@echo "Available commands:"
	@echo "  make fixer   - format + analyze + metrics (cs-fixer + phpstan analogue)"
	@echo "  make format  - dart format"
	@echo "  make analyze - flutter analyze"
	@echo "  make metrics - dart_code_metrics"
	@echo "  make test    - flutter test"

# -------------------------
# 🔥 Main target
# -------------------------

fixer: format analyze metrics
	@echo "✔ fixer completed successfully"

# -------------------------
# Formatting (dart format)
# -------------------------

format:
	@echo "🧹 Formatting Dart code..."
	cd app && $(DART) format $(LIB) $(TEST)

# -------------------------
# Static analysis (flutter_lints)
# -------------------------

analyze:
	@echo "🔍 Running flutter analyze..."
	cd app && $(FLUTTER) analyze

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
