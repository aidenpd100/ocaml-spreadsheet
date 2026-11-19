let () =
  Dream.run ~port:8080
  @@ Dream.router [
    Dream.get "/" (fun _ ->
      Dream.html "Hello from Camlsheet!");
  ]