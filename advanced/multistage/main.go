package main

import (
    "fmt"
    "net/http"
    "os"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Hello from multistage! UID=%d\n", os.Getuid())
    })
    if err := http.ListenAndServe(":8080", nil); err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
}
