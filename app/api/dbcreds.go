package main

import (
	"context"
	"database/sql/driver"
	"fmt"
	"net/url"
	"os"
	"strings"

	"github.com/lib/pq"
)

// fileCredentialConnector opens each new Postgres connection with the
// username and password currently in two files (DB_USER_FILE and
// DB_PASSWORD_FILE), on top of a DATABASE_URL that carries no credentials.
//
// This is what lets the API survive a password rotation (session 12): the
// CSI driver rewrites the files when Vault rotates the password, connections
// already open keep working (Postgres does not drop them), and the next
// connection the pool opens picks up the new password. Reading the password
// once at boot, from an env var, is what breaks on the first rotation.
type fileCredentialConnector struct {
	baseURL      string
	userFile     string
	passwordFile string
}

func (c fileCredentialConnector) Connect(ctx context.Context) (driver.Conn, error) {
	dsn, err := c.dsn()
	if err != nil {
		return nil, err
	}
	connector, err := pq.NewConnector(dsn)
	if err != nil {
		return nil, err
	}
	return connector.Connect(ctx)
}

func (c fileCredentialConnector) Driver() driver.Driver {
	return &pq.Driver{}
}

func (c fileCredentialConnector) dsn() (string, error) {
	user, err := readTrimmed(c.userFile)
	if err != nil {
		return "", err
	}
	password, err := readTrimmed(c.passwordFile)
	if err != nil {
		return "", err
	}
	u, err := url.Parse(c.baseURL)
	if err != nil {
		return "", fmt.Errorf("parse DATABASE_URL: %w", err)
	}
	u.User = url.UserPassword(user, password)
	return u.String(), nil
}

func readTrimmed(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read credential file: %w", err)
	}
	return strings.TrimSpace(string(b)), nil
}
