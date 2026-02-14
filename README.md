# Web Stresser Panel

A high-performance, open-source IP stresser panel featuring a modern dark-themed dashboard, Discord bot integration, and a flexible API management system.

### 👑 Created by [devilscancry](https://github.com/devilscancry) (better known as Pinky)

---

## ✨ Features

- 🖥️ **Modern Dashboard**: sleek, responsive UI with real-time statistics and glassmorphism design.
- 🚀 **Attack Hub**: Dedicated page for launching attacks and monitoring running processes.
- 🤖 **Discord Bot**: Create and manage users directly from your Discord server.
- 🔍 **IP Lookup**: Integrated tool to retrieve geolocation and info for IP addresses.
- 🔒 **Secure**: JWT-based authentication, bcrypt password hashing, and forced password changes.
- ⚙️ **Flexible APIs**: Easily configure multiple attack APIs via `apis.json`.
- 📊 **Auto-Database**: Automatically initializes tables and schemas on first run.

---

## 📋 Prerequisites

- **Go (Golang)**: Version 1.19 or higher.
- **Database**: MySQL or MariaDB.
- **Git**: To clone the repository.

---

## 🔗 API Management

If you can't handle your servers with your own API manager, you are free to use **Pinky's Remorse API Manager**:

👉 [https://github.com/devilscancry/remorse-api-manager](https://github.com/devilscancry/remorse-api-manager)

---

## 🪟 Windows Installation

1.  **Install Go**: Download and install from go.dev.
2.  **Install MySQL/MariaDB**: Set up a local database server.
3.  **Clone the Repo**:
    ```powershell
    git clone https://github.com/devilscancry/web-stresser-src.git
    cd web-stresser-src
    ```
4.  **Configuration**:
    - Ensure `config.json` exists in the root directory.
    - Update the `db_user`, `db_password`, and `discord_bot_token` fields.
5.  **Install Dependencies**:
    ```powershell
    go mod tidy
    ```
6.  **Run**:
    ```powershell
    go run main.go
    ```
    The panel will be accessible at `http://localhost:8054` (or your configured port).

---

## 🐧 Linux Installation (Ubuntu/Debian)

1.  **Update & Install Dependencies**:
    ```bash
    sudo apt update && sudo apt upgrade -y
    sudo apt install golang mariadb-server git -y
    ```

2.  **Setup Database**:
    ```bash
    sudo mysql_secure_installation
    # Log into MySQL
    sudo mysql -u root -p
    ```
    Inside the MySQL shell:
    ```sql
    CREATE DATABASE stresser;
    CREATE USER 'stresser'@'localhost' IDENTIFIED BY 'your_secure_password';
    GRANT ALL PRIVILEGES ON stresser.* TO 'stresser'@'localhost';
    FLUSH PRIVILEGES;
    EXIT;
    ```

3.  **Clone & Configure**:
    ```bash
    git clone https://github.com/devilscancry/web-stresser-src.git
    cd web-stresser-src
    
    # Edit config.json with your new database credentials
    nano config.json
    ```

4.  **Run**:
    ```bash
    go mod tidy
    go run main.go
    ```
    *Tip: Use `screen` or `systemd` to keep it running in the background.*

---

## 🤖 Discord Bot Commands

The bot token must be set in `config.json`.

- **Create User**:
  `!createuser <email> <password> <plan> <max_time> <concurrents>`
  *Example:* `!createuser client@email.com Pass123 VIP 1200 2`

- **Update User Limits**:
  `!updateuser <email> <max_time|concurrents> <value>`
  *Example:* `!updateuser client@email.com max_time 3600`

---

## ⚠️ Disclaimer

This software is provided for educational purposes and authorized stress testing only.

**Author**: devilscancry (Pinky)

*Do not use this software for illegal purposes. The creator is not responsible for any damage caused by the misuse of this tool.*