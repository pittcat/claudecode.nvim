.PHONY: check format test clean

# Default target
all: format check test

# Detect available tools
HAS_NIX := $(shell command -v nix 2> /dev/null)
HAS_LUA := $(shell command -v lua 2> /dev/null)
HAS_LUACHECK := $(shell command -v luacheck 2> /dev/null)

# Determine prefix to use
ifdef HAS_NIX
ifeq (,$(IN_NIX_SHELL))
NIX_PREFIX := nix develop .#ci -c
else
NIX_PREFIX :=
endif
else
NIX_PREFIX :=
endif

# Check for syntax errors
check:
	@echo "Checking Lua files for syntax errors..."
ifndef HAS_LUA
	$(error "lua command not found. Please install lua: brew install lua")
endif
	$(NIX_PREFIX) find lua -name "*.lua" -type f -exec lua -e "assert(loadfile('{}'))" \;
	@echo "Running luacheck..."
ifndef HAS_LUACHECK
	$(error "luacheck command not found. Please install luacheck: brew install luacheck")
endif
	$(NIX_PREFIX) luacheck lua/ tests/ --no-unused-args --no-max-line-length

# Format all files
format:
ifdef HAS_NIX
	nix fmt
else
	@echo "Formatting with stylua (if available)..."
	@if command -v stylua >/dev/null 2>&1; then \
		stylua lua/ tests/; \
	else \
		echo "stylua not found. Install with: brew install stylua"; \
		echo "Skipping formatting..."; \
	fi
endif

# Run tests
test:
	@echo "Running all tests..."
	@if ! command -v busted >/dev/null 2>&1; then \
		echo "busted not found. Install with: brew install luarocks && luarocks install busted"; \
		exit 1; \
	fi
	@export LUA_PATH="./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;$$LUA_PATH"; \
	TEST_FILES=$$(find tests -type f -name "*_test.lua" -o -name "*_spec.lua" | sort); \
	echo "Found test files:"; \
	echo "$$TEST_FILES"; \
	if [ -n "$$TEST_FILES" ]; then \
		if command -v luacov >/dev/null 2>&1; then \
			$(NIX_PREFIX) busted --coverage -v $$TEST_FILES; \
		else \
			echo "LuaCov not found, running tests without coverage..."; \
			$(NIX_PREFIX) busted -v $$TEST_FILES; \
		fi; \
	else \
		echo "No test files found"; \
	fi

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	@rm -f luacov.report.out luacov.stats.out
	@rm -f tests/lcov.info

# Print available commands
help:
	@echo "Available commands:"
	@echo "  make check  - Check for syntax errors"
	@echo "  make format - Format all files (uses nix fmt or stylua)"
	@echo "  make test   - Run tests"
	@echo "  make clean  - Clean generated files"
	@echo "  make help   - Print this help message"
