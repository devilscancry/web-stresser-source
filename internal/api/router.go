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
