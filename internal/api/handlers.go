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

	if err := h.DB.CreateUser(creds.Email, hashedPassword, "Free", 30, 1, false); err != nil {
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
