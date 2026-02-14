package database

import (
	"database/sql"
	"fmt"
	"log"
	"time"
	"webstresser/internal/models"

	_ "github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
)

type DB struct {
	*sqlx.DB
}

func New(config *models.Config) (*DB, error) {
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true",
		config.DBUser, config.DBPassword, config.DBHost, config.DBPort, config.DBName)

	db, err := sqlx.Connect("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	log.Println("Successfully connected to the database.")

	if err := initSchema(db); err != nil {
		return nil, fmt.Errorf("failed to initialize database schema: %w", err)
	}

	return &DB{db}, nil
}

func (db *DB) GetUserByEmail(email string) (*models.User, error) {
	user := &models.User{}
	query := `
        SELECT 
            u.id, u.email, u.password_hash, u.plan_id, 
            u.max_time, u.max_concurrents, u.cooldown, u.is_vip, u.force_password_change,
            u.last_attack_time, u.active_attacks, u.created_at,
            p.name as plan_name
        FROM users u
        JOIN plans p ON u.plan_id = p.id
        WHERE u.email = ?`
	err := db.Get(user, query, email)
	if err != nil {
		return nil, err
	}
	return user, nil
}

func (db *DB) GetUserByID(id int) (*models.User, error) {
	user := &models.User{}
	query := `
        SELECT 
            u.id, u.email, u.password_hash, u.plan_id, 
            u.max_time, u.max_concurrents, u.cooldown, u.is_vip, u.force_password_change,
            u.last_attack_time, u.active_attacks, u.created_at,
            p.name as plan_name
        FROM users u
        JOIN plans p ON u.plan_id = p.id
        WHERE u.id = ?`
	err := db.Get(user, query, id)
	if err != nil {
		return nil, err
	}
	return user, nil
}

func (db *DB) CreateUser(email, passwordHash, planName string, maxTime, maxConcurrents int, forceChange bool) error {
	var plan models.Plan
	err := db.Get(&plan, "SELECT * FROM plans WHERE name = ?", planName)
	if err != nil {
		if err == sql.ErrNoRows {
			return fmt.Errorf("plan '%s' not found", planName)
		}
		return err
	}

	query := "INSERT INTO users (email, password_hash, plan_id, max_time, max_concurrents, cooldown, is_vip, force_password_change) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
	_, err = db.Exec(query, email, passwordHash, plan.ID, maxTime, maxConcurrents, plan.Cooldown, plan.IsVIP, forceChange)
	return err
}

func (db *DB) UpdateUserLimit(email string, limitType string, value int) error {
	var column string
	switch limitType {
	case "max_time":
		column = "max_time"
	case "concurrents":
		column = "max_concurrents"
	default:
		return fmt.Errorf("invalid limit type: use 'max_time' or 'concurrents'")
	}
	query := fmt.Sprintf("UPDATE users SET %s = ? WHERE email = ?", column)
	_, err := db.Exec(query, value, email)
	return err
}

func (db *DB) UpdateLastAttackTime(userID int, lastAttackTime *time.Time) error {
	query := "UPDATE users SET last_attack_time = ? WHERE id = ?"
	_, err := db.Exec(query, lastAttackTime, userID)
	return err
}

func (db *DB) RecordAttack(userID int, target string, port, duration int, method string) error {
	query := `INSERT INTO attacks (user_id, target, port, duration, method, end_time) 
              VALUES (?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))`
	_, err := db.Exec(query, userID, target, port, duration, method, duration)
	return err
}

func (db *DB) GetRunningAttacks(userID int) ([]models.Attack, error) {
	var attacks []models.Attack
	err := db.Select(&attacks, "SELECT * FROM attacks WHERE user_id = ? AND end_time > NOW() ORDER BY end_time ASC", userID)
	return attacks, err
}

func (db *DB) GetActiveAttackCount(userID int) (int, error) {
	var count int
	err := db.Get(&count, "SELECT COUNT(*) FROM attacks WHERE user_id = ? AND end_time > NOW()", userID)
	return count, err
}

func (db *DB) UpdatePassword(userID int, newHash string) error {
	_, err := db.Exec("UPDATE users SET password_hash = ?, force_password_change = 0 WHERE id = ?", newHash, userID)
	return err
}

func initSchema(db *sqlx.DB) error {
	queries := []string{
		`CREATE TABLE IF NOT EXISTS plans (
			id INT AUTO_INCREMENT PRIMARY KEY,
			name VARCHAR(50) NOT NULL UNIQUE,
			max_time INT NOT NULL,
			max_concurrents INT NOT NULL,
			cooldown INT NOT NULL,
			is_vip BOOLEAN NOT NULL DEFAULT FALSE
		);`,
		`CREATE TABLE IF NOT EXISTS users (
			id INT AUTO_INCREMENT PRIMARY KEY,
			email VARCHAR(255) NOT NULL UNIQUE,
			password_hash VARCHAR(255) NOT NULL,
			plan_id INT NOT NULL,
			max_time INT NOT NULL,
			max_concurrents INT NOT NULL,
			cooldown INT NOT NULL,
			is_vip BOOLEAN NOT NULL DEFAULT FALSE,
			force_password_change BOOLEAN NOT NULL DEFAULT FALSE,
			last_attack_time TIMESTAMP NULL,
			active_attacks INT NOT NULL DEFAULT 0,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (plan_id) REFERENCES plans(id)
		);`,
		`CREATE TABLE IF NOT EXISTS attacks (
			id INT AUTO_INCREMENT PRIMARY KEY,
			user_id INT NOT NULL,
			target VARCHAR(255) NOT NULL,
			port INT NOT NULL,
			duration INT NOT NULL,
			method VARCHAR(50) NOT NULL,
			start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			end_time TIMESTAMP NULL,
			FOREIGN KEY (user_id) REFERENCES users(id)
		);`,
		`INSERT INTO plans (name, max_time, max_concurrents, cooldown, is_vip) VALUES 
		('Free', 30, 1, 60, FALSE),
		('VIP', 300, 4, 15, TRUE)
		ON DUPLICATE KEY UPDATE name=name;`,
	}

	for _, query := range queries {
		if _, err := db.Exec(query); err != nil {
			return fmt.Errorf("error executing schema query: %w", err)
		}
	}

	// Migrations for existing tables
	migrations := []struct {
		Column string
		Query  string
	}{
		{"max_time", "ALTER TABLE users ADD COLUMN max_time INT NOT NULL DEFAULT 30"},
		{"max_concurrents", "ALTER TABLE users ADD COLUMN max_concurrents INT NOT NULL DEFAULT 1"},
		{"cooldown", "ALTER TABLE users ADD COLUMN cooldown INT NOT NULL DEFAULT 60"},
		{"is_vip", "ALTER TABLE users ADD COLUMN is_vip BOOLEAN NOT NULL DEFAULT FALSE"},
		{"force_password_change", "ALTER TABLE users ADD COLUMN force_password_change BOOLEAN NOT NULL DEFAULT FALSE"},
	}

	for _, m := range migrations {
		checkQuery := fmt.Sprintf("SELECT %s FROM users LIMIT 1", m.Column)
		rows, err := db.Query(checkQuery)
		if err != nil {
			if _, err := db.Exec(m.Query); err != nil {
				log.Printf("Migration error: failed to add column %s: %v", m.Column, err)
			} else {
				log.Printf("Migration success: added column %s", m.Column)
			}
		} else {
			rows.Close()
		}
	}

	return nil
}
