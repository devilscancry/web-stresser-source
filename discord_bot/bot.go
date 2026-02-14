package discord_bot

import (
	"fmt"
	"log"
	"strconv"
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
		if len(parts) != 6 {
			s.ChannelMessageSend(m.ChannelID, "Usage: `!createuser <email> <password> <plan_name> <max_time> <concurrents>`")
			return
		}

		email := parts[1]
		password := parts[2]
		planName := parts[3]
		maxTime, err := strconv.Atoi(parts[4])
		if err != nil {
			s.ChannelMessageSend(m.ChannelID, "Invalid max_time value.")
			return
		}
		concurrents, err := strconv.Atoi(parts[5])
		if err != nil {
			s.ChannelMessageSend(m.ChannelID, "Invalid concurrents value.")
			return
		}

		hashedPassword, err := auth.HashPassword(password)
		if err != nil {
			log.Printf("Error hashing password for discord user creation: %v", err)
			s.ChannelMessageSend(m.ChannelID, "Error creating user: could not process password.")
			return
		}

		err = b.DB.CreateUser(email, hashedPassword, planName, maxTime, concurrents, true)
		if err != nil {
			log.Printf("Error creating user from discord: %v", err)
			s.ChannelMessageSend(m.ChannelID, fmt.Sprintf("Error creating user: %s", err.Error()))
			return
		}

		s.ChannelMessageSend(m.ChannelID, fmt.Sprintf("[OK] User `%s` created successfully with plan `%s`.", email, planName))
	}

	if strings.HasPrefix(m.Content, "!updateuser") {
		parts := strings.Fields(m.Content)
		if len(parts) != 4 {
			s.ChannelMessageSend(m.ChannelID, "Usage: `!updateuser <email> <max_time|concurrents> <value>`")
			return
		}

		email := parts[1]
		limitType := parts[2]
		value, err := strconv.Atoi(parts[3])
		if err != nil {
			s.ChannelMessageSend(m.ChannelID, "Invalid value.")
			return
		}

		err = b.DB.UpdateUserLimit(email, limitType, value)
		if err != nil {
			log.Printf("Error updating user: %v", err)
			s.ChannelMessageSend(m.ChannelID, fmt.Sprintf("Error updating user: %s", err.Error()))
			return
		}

		s.ChannelMessageSend(m.ChannelID, fmt.Sprintf("[OK] Updated `%s` for user `%s` to `%d`.", limitType, email, value))
	}
}
