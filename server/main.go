package main

import (
	"log"
	"os"
	"strings"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"

	_ "github.com/couples-app/server/migrations"
)

func main() {
	app := pocketbase.New()

	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{
		// generate Go migration files from Admin UI changes during development
		Automigrate: strings.HasPrefix(os.Getenv("COUPLES_ENV"), "dev"),
		Dir:         "migrations",
	})

	bindRoutes(app)

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
