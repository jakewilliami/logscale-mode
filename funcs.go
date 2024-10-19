package main

import (
	"context"
	"fmt"
	"os"
	"strings"

	// https://stackoverflow.com/a/74328802
	"github.com/nfx/go-htmltable"
)

type Function struct {
	Function string `header:"Function"`
	Type string `header:"Type"`
	Default string `header:"Default Argument"`
	Availability string `header:"Availability"`
	Description string `header:"Description"`
}

func extractFunc(funcRaw string) string {
	// Find the index of the first parenthesis
	startIndex := strings.Index(funcRaw, "(")
	if startIndex == -1 {
		// Return the original string if there's no parenthesis
		return funcRaw
	}
	// Extract the substring up to the first parenthesis
	return funcRaw[:startIndex]
}

func main() {
	htmltable.Logger = func(_ context.Context, msg string, fields ...any) {
		fmt.Printf("[INFO] %s %v\n", msg, fields)
	}

	url := "https://library.humio.com/data-analysis/functions.html"
	table, err := htmltable.NewSliceFromURL[Function](url)
	if err != nil {
		fmt.Printf("[ERROR] Could not get table by %s: %s", url, err)
		os.Exit(1)
	}

	for i := 0; i < len(table); i++ {
		fmt.Printf("\"%s\" ", extractFunc(table[i].Function))
	}
}
