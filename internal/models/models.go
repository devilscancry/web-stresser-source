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
