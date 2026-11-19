let () =
  Dream.run
  @@ Dream.logger
  @@ Dream.router [
    Dream.get "/api/cells" Routes.get_cells;
    Dream.get "/api/cells/:coord" Routes.get_cell;
    Dream.put "/api/cells/:coord" Routes.update_cell;

    Dream.get "/api/save" Routes.save_sheet;
    Dream.post "/api/load" Routes.load_sheet;

    Dream.post "/api/undo" Routes.undo;
    Dream.post "/api/redo" Routes.redo;
    Dream.get "/api/history" Routes.get_history;
  ]