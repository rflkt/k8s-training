package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

// Item represents a row in the items table.
type Item struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}

// Version is set at build time via -ldflags.
var version = "1.0"

var db *sql.DB

func main() {
	port := getEnv("PORT", "8080")

	// Connect to Postgres if DATABASE_URL is set
	if dbURL := os.Getenv("DATABASE_URL"); dbURL != "" {
		var err error
		db, err = sql.Open("postgres", dbURL)
		if err != nil {
			log.Fatalf("Failed to open database connection: %v", err)
		}
		defer db.Close()

		// Retry connecting to the database (handles container startup ordering)
		for i := 0; i < 30; i++ {
			if err := db.Ping(); err == nil {
				break
			}
			log.Printf("Waiting for database... (%d/30)", i+1)
			time.Sleep(time.Second)
		}
		if err := db.Ping(); err != nil {
			log.Fatalf("Failed to connect to database after 30s: %v", err)
		}
		log.Println("Connected to database")

		// Create items table if it does not exist
		if err := createTable(); err != nil {
			log.Fatalf("Failed to create items table: %v", err)
		}
	} else {
		log.Println("DATABASE_URL not set — running without database")
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/ready", handleReady)
	mux.HandleFunc("/info", handleInfo)
	mux.HandleFunc("/items", handleItems)
	mux.HandleFunc("/items/", handleItemByID)
	mux.HandleFunc("/secret-test", handleSecretTest)

	handler := loggingMiddleware(mux)

	log.Printf("Starting server on :%s", port)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

// loggingMiddleware logs each incoming request to stdout.
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}

// getEnv returns the value of an environment variable or a default.
func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// writeJSON writes a JSON response with the given status code.
func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// createTable ensures the items table exists.
func createTable() error {
	query := `
		CREATE TABLE IF NOT EXISTS items (
			id SERIAL PRIMARY KEY,
			name TEXT NOT NULL,
			created_at TIMESTAMP DEFAULT NOW()
		);
	`
	_, err := db.Exec(query)
	return err
}

// --- Handlers ---

func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	hostname, _ := os.Hostname()
	writeJSON(w, http.StatusOK, map[string]string{
		"message":  fmt.Sprintf("Hello from k8s-training! (v%s)", version),
		"version":  version,
		"hostname": hostname,
	})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"status": "ok",
	})
}

func handleReady(w http.ResponseWriter, r *http.Request) {
	// If a database is configured, check its connectivity
	if db != nil {
		if err := db.Ping(); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{
				"status": "not ready",
				"error":  err.Error(),
			})
			return
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"status": "ready",
	})
}

func handleInfo(w http.ResponseWriter, r *http.Request) {
	env := getEnv("ENVIRONMENT", "development")
	writeJSON(w, http.StatusOK, map[string]string{
		"version":     version,
		"environment": env,
	})
}

func handleItems(w http.ResponseWriter, r *http.Request) {
	if db == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"error": "database not configured",
		})
		return
	}

	switch r.Method {
	case http.MethodGet:
		listItems(w, r)
	case http.MethodPost:
		createItem(w, r)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func handleItemByID(w http.ResponseWriter, r *http.Request) {
	if db == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"error": "database not configured",
		})
		return
	}

	// Extract ID from /items/{id}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/items/"), "/")
	id, err := strconv.Atoi(parts[0])
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid item id",
		})
		return
	}

	switch r.Method {
	case http.MethodGet:
		getItem(w, r, id)
	case http.MethodDelete:
		deleteItem(w, r, id)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func handleSecretTest(w http.ResponseWriter, r *http.Request) {
	path := getEnv("API_KEY_PATH", "/mnt/secrets-store/api-key")

	if _, err := os.Stat(path); err == nil {
		writeJSON(w, http.StatusOK, map[string]string{
			"secret_exists": "true",
			"path":          path,
		})
	} else {
		writeJSON(w, http.StatusOK, map[string]string{
			"secret_exists": "false",
			"path":          path,
		})
	}
}

// --- Item CRUD ---

func listItems(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query("SELECT id, name, created_at FROM items ORDER BY id")
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	defer rows.Close()

	items := []Item{}
	for rows.Next() {
		var item Item
		if err := rows.Scan(&item.ID, &item.Name, &item.CreatedAt); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		items = append(items, item)
	}

	writeJSON(w, http.StatusOK, items)
}

func createItem(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return
	}
	if input.Name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "name is required"})
		return
	}

	var item Item
	err := db.QueryRow(
		"INSERT INTO items (name) VALUES ($1) RETURNING id, name, created_at",
		input.Name,
	).Scan(&item.ID, &item.Name, &item.CreatedAt)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusCreated, item)
}

func getItem(w http.ResponseWriter, r *http.Request, id int) {
	var item Item
	err := db.QueryRow(
		"SELECT id, name, created_at FROM items WHERE id = $1", id,
	).Scan(&item.ID, &item.Name, &item.CreatedAt)
	if err == sql.ErrNoRows {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": fmt.Sprintf("item %d not found", id)})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, item)
}

func deleteItem(w http.ResponseWriter, r *http.Request, id int) {
	result, err := db.Exec("DELETE FROM items WHERE id = $1", id)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	rows, _ := result.RowsAffected()
	if rows == 0 {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": fmt.Sprintf("item %d not found", id)})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"message": fmt.Sprintf("item %d deleted", id)})
}
