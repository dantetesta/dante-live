#!/usr/bin/env python3
"""Offline protocol smoke test for the native MCP stdio executable."""
import json
import subprocess
import sys

binary = sys.argv[1]
requests = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "not_a_tool", "arguments": {}}},
    {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "studio_overview", "arguments": {}}},
]
input_data = "".join(json.dumps(request) + "\n" for request in requests)
process = subprocess.run([binary], input=input_data, text=True, capture_output=True, timeout=10, check=True)
answers = [json.loads(line) for line in process.stdout.splitlines()]
assert [answer["id"] for answer in answers] == [1, 2, 3, 4]
assert answers[0]["result"]["protocolVersion"] == "2025-11-25"
assert "tools" in answers[0]["result"]["capabilities"]
names = {tool["name"] for tool in answers[1]["result"]["tools"]}
assert names == {
    "studio_overview", "scene_items", "source_types", "source_options",
    "scene_create", "scene_rename", "scene_select", "source_add", "source_update",
    "source_reuse", "item_transform", "item_visibility", "item_order", "studio_undo",
}, "MCP tool changes require explicit contract review"
for tool in answers[1]["result"]["tools"]:
    schema = tool["inputSchema"]
    assert schema["type"] == "object" and schema["additionalProperties"] is False
    assert set(schema["required"]) <= set(schema["properties"])
assert answers[2]["error"]["code"] == -32602
assert answers[3]["result"]["content"][0]["type"] == "text"
assert isinstance(answers[3]["result"]["isError"], bool)
print("PASS: MCP initialize, notification, tool discovery, unknown-tool rejection and app call")
