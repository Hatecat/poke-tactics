extends SceneTree
## Lanza el servidor del modo VS (VsRelay, scripts/net/vs_relay.gd) desde el proyecto:
##
##     godot --headless --path . --script tools/vs_server.gd [-- puerto] [--quiet]


func _initialize() -> void:
	root.add_child.call_deferred(load("res://scripts/net/vs_relay.gd").new())
