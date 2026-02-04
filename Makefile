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
	@echo "📊 Running dart_code_metrics..."
	cd app && $(DART) run dart_code_metrics:metrics analyze $(LIB) --disable-sunset-warning

# -------------------------
# Tests
# -------------------------

tests:
	@echo "🧪 Running tests..."
	cd app && $(FLUTTER) test
