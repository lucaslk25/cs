# Crystal Server - Setup Guide

## Prerequisites

- MySQL/MariaDB installed and running
- vcpkg installed at ~/repos/vcpkg
- VCPKG_ROOT environment variable set

## Initial Setup

### 1. Database Configuration

Edit config.lua:

mysqlHost = "127.0.0.1"
mysqlUser = "your_user"
mysqlPass = "your_password"
mysqlDatabase = "crystal"

Import schema:
mysql -u your_user -p < schema.sql

### 2. Map Files

Check if world map exists:
ls -lh data-global/world/world.otbm

If compressed, decompress it first.

Verify config.lua dataPackDirectory setting.

### 3. Compile

cmake --preset linux-debug
cmake --build --preset linux-debug -j$(nproc)

Or use: ./dev.sh build-only

### 4. Start Server

./dev.sh run-only

Logs: tail -f /tmp/crystalserver.log
Stop: pkill -f crystalserver-debug

## OTClient Setup

1. Copy assets folder from GameClient to OTClient/data/things/{version}/
2. Configure connection: 127.0.0.1:7171
3. Run OTClient

## Quick Commands

./dev.sh              # Compile + Run
./dev.sh build-only   # Compile only
./dev.sh run-only     # Run only
pgrep -f crystalserver-debug  # Check if running
tail -f /tmp/crystalserver.log  # View logs
