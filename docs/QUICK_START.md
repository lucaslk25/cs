# Crystal Server - Quick Start Guide

## Server Setup

### 1. Configure MySQL Database

Edit `config.lua` in the root directory:

```lua
-- MySQL Database Configuration
mysqlHost = "127.0.0.1"
mysqlUser = "your_mysql_user"
mysqlPass = "your_mysql_password"
mysqlDatabase = "crystalserver"
mysqlPort = 3306
```

### 2. Verify World Data

Check the world name in `config.lua`:

```lua
-- World Configuration
worldName = "Crystal"
worldType = "pvp"
```

Ensure the corresponding world folder exists:
- Path: `data-global/world/`
- If the world data is compressed (`.zip`, `.rar`, etc.), extract it to this folder
- The folder should contain map files (`.otbm`) and spawn data

### 3. Start the Server

```bash
cd /path/to/crystalserver
./crystalserver
```

Wait for the server to fully initialize. Look for messages indicating:
- Database connection successful
- Map loaded
- Spawns loaded
- Server ready to accept connections

---

## OTClient Setup

### 1. Add Game Assets

Copy the `assets` folder from the official Tibia client to the OTClient data folder:

**Source:** `GameClient/assets/`  
**Destination:** `otclient/data/things/{version}/`

Where `{version}` is your client version (e.g., `1098`, `1200`, `1340`, etc.)

The assets folder should contain:
- `Tibia.dat`
- `Tibia.spr`
- Or equivalent `.dat` and `.spr` files for your version

### 2. Launch OTClient

Run the OTClient executable:

**Windows:**
```cmd
otclient.exe
```

**Linux:**
```bash
./otclient
```

### 3. Connect to Server

1. Enter server IP address (default: `127.0.0.1` for localhost)
2. Enter port (default: `7172`)
3. Enter account credentials
4. Select character and play

---

## Troubleshooting

### Server Issues

**Database connection failed:**
- Verify MySQL is running
- Check credentials in `config.lua`
- Ensure database exists and schema is imported

**Map not found:**
- Check `data-global/world/` folder exists
- Verify map files are extracted (not compressed)
- Check world name matches configuration

### Client Issues

**Missing sprites/graphics:**
- Verify assets are in correct `data/things/{version}/` folder
- Ensure client version matches server protocol
- Check file permissions (files must be readable)

**Cannot connect:**
- Verify server is running
- Check firewall settings
- Confirm IP address and port are correct
- Ensure client protocol version matches server

---

## Quick Reference

| Component | Default Value |
|-----------|---------------|
| MySQL Host | 127.0.0.1 |
| MySQL Port | 3306 |
| Server Port | 7172 |
| World Folder | data-global/world/ |
| Client Assets | data/things/{version}/ |

---

## Next Steps

After successful setup:
- Create admin account (see `docs/ADMIN_SETUP.md`)
- Configure server features in `config.lua`
- Customize game content in `data-crystal/` folder
- Review security settings for production deployment
