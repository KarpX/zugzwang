---
name: godot-mcp-workflow
description: Workflow for leveraging the live Godot MCP server for syntax validation, scene inspection, runtime logs, and test execution.
---

# Godot MCP Workflow Skill

## Overview
This project has an active live Godot MCP server (`addons/godot_mcp` running on `ws://127.0.0.1:6505`).
For full in-depth documentation and troubleshooting, see [`docs/GODOT_MCP.md`](../../docs/GODOT_MCP.md).

Always leverage Godot MCP tools before guessing node structures or committing unchecked scripts.

---

## 1. Pre-Commit Script Validation
Never commit GDScript changes without running:
```json
{
  "ServerName": "godot",
  "ToolName": "validate_script",
  "Arguments": {
    "path": "res://scripts/chess/chess_board.gd"
  }
}
```
If new files or assets were written directly to the file system, trigger a filesystem rescan in the editor:
```json
{
  "ServerName": "godot",
  "ToolName": "rescan_filesystem",
  "Arguments": {}
}
```

---

## 2. Scene Tree Inspection & Node Editing
- Inspect active hierarchy in editor:
  ```json
  { "ServerName": "godot", "ToolName": "scene_tree_dump", "Arguments": {} }
  ```
- Inspect a specific scene from disk:
  ```json
  { "ServerName": "godot", "ToolName": "read_scene", "Arguments": { "path": "res://scenes/room.tscn" } }
  ```
- Add a node or instance a child scene:
  ```json
  {
    "ServerName": "godot",
    "ToolName": "instance_scene",
    "Arguments": {
      "target_scene_path": "res://scenes/room.tscn",
      "parent_node_path": ".",
      "instance_scene_path": "res://scenes/chess/chess_table.tscn",
      "instance_name": "ChessTable"
    }
  }
  ```

---

## 3. The Interactive Runtime Testing Loop
Drive the running game directly to verify gameplay mechanics:

1. **Launch Scene**:
   ```json
   {
     "ServerName": "godot",
     "ToolName": "run_scene",
     "Arguments": {
       "scene_path": "res://scenes/room.tscn",
       "wait_for_runtime": true
     }
   }
   ```
2. **Check Startup Errors**:
   ```json
   { "ServerName": "godot", "ToolName": "get_errors", "Arguments": { "max_errors": 20 } }
   ```
3. **Send Input / Drive Interaction**:
   ```json
   {
     "ServerName": "godot",
     "ToolName": "send_input",
     "Arguments": {
       "event": {
         "type": "action",
         "action": "Forward",
         "pressed": true
       }
     }
   }
   ```
4. **Inspect Live State**:
   ```json
   {
     "ServerName": "godot",
     "ToolName": "query_runtime_node",
     "Arguments": {
       "node_path": "/root/EventBus",
       "properties": ["total_losses", "current_stage", "is_in_board_mode"]
     }
   }
   ```
5. **Capture Screenshot**:
   ```json
   { "ServerName": "godot", "ToolName": "take_screenshot", "Arguments": {} }
   ```
6. **Stop Scene**:
   ```json
   { "ServerName": "godot", "ToolName": "stop_scene", "Arguments": {} }
   ```
