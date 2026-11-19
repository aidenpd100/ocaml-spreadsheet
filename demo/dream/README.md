# Dream Library Demo

## Purpose
This demo verifies that the Dream web framework can successfully run an HTTP server written in OCaml.

## Library
- Dream (`1.0.0~alpha8`)

## How to Run

From the root of the repository, run:

```bash
dune exec ./demo/dream/main.exe
```

Open `http://localhost:8080` in a browser.

## Expected Output

The browser should display:

```text
Hello from Camlsheet!
```

## Result

The demo successfully starts a Dream server and handles an HTTP GET request, confirming that Dream can be used for the Camlsheet backend.