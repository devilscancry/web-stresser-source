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
