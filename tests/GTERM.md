# Client diagnostics from a dedicated-server GTerm

GTerm attached to `srcds` can only execute server Lua directly. The opt-in bridge
in `lua/pocketmap/dev/sv_gterm.lua` sends client Lua to the connected player with
`Player:SendLua` and relays the result back to the server console. It handles
scripts larger than the engine's 6144-byte message limit by sending chunks.
It does not require `sv_allowcslua`.

In GTerm, run:

```text
lua_run include('pocketmap/dev/sv_gterm.lua')
lua_run PocketMap.GTerm.Run('return 6*7')
lua_run PocketMap.GTerm.RunFile('pocketmap/dev/cl_mapio_probe.lua')
```

The console prints `[PocketMap client #N player] OK: ...` or `ERROR: ...`.
The bridge targets the first connected player by default. `Run(code, ply)`
and `RunFile(path, ply)` accept an explicit player as their second argument.
Script files are read on the server and executed in the client's Lua realm.
The bridge must be loaded manually after a server restart.

Other probes:

```text
lua_run PocketMap.GTerm.RunFile('pocketmap/dev/cl_button_smoke.lua')
lua_run PocketMap.GTerm.RunFile('pocketmap/dev/cl_miniature_status.lua')
lua_run PocketMap.GTerm.RunFile('pocketmap/dev/cl_refresh_mapio.lua')
lua_run PocketMap.GTerm.RunFile('pocketmap/dev/cl_reload_miniature.lua')
```

`cl_button_smoke.lua` simulates one E press at the button currently under the
virtual crosshair, dispatches its outputs, and reports the linked door state.
`cl_refresh_mapio.lua` rebuilds the active walking session's I/O index. If a
miniature loaded before the handlers were registered, its old static geometry
also needs rebuilding: `cl_reload_miniature.lua` reloads the block and exits
the current walk. Enter the map again once loading finishes.

After installing new client files while a server is already running, restart
the server to register them for ordinary client joins, or reload the server
autorun file and send the updated client code through this bridge for a live
debug session.
