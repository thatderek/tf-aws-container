package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", HandlerFunc)
	http.ListenAndServe(":8080", nil)
}

func HandlerFunc(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "Hello from ecs task: %s", os.Getenv("APP_EXAMPLE_STRING"))
}
