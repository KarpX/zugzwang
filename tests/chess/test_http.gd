extends SceneTree

func _init() -> void:
	print("Testing HTTPClient poll...")
	var http = HTTPClient.new()
	var err = http.connect_to_host("lichess.org", 443, TLSOptions.client())
	if err != OK:
		print("Connect error: ", err)
		quit(1)
		return
		
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		OS.delay_msec(20)
		
	print("Connected! Status: ", http.get_status())
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		print("Not connected: ", http.get_status())
		quit(1)
		return
		
	var path = "/api/cloud-eval?fen=rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR%20w%20KQkq%20-%200%201"
	var headers = PackedStringArray([
		"User-Agent: ZugzwangGame/1.0",
		"Accept: application/json"
	])
	err = http.request(HTTPClient.METHOD_GET, path, headers)
	if err != OK:
		print("Request error: ", err)
		quit(1)
		return
		
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		OS.delay_msec(20)
		
	print("Request done! Status: ", http.get_status())
	if http.has_response():
		print("Response code: ", http.get_response_code())
		var rb = PackedByteArray()
		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			var chunk = http.read_response_body_chunk()
			if chunk.size() > 0:
				rb.append_array(chunk)
			else:
				OS.delay_msec(10)
		var text = rb.get_string_from_utf8()
		print("Body: ", text.left(120))
	quit(0)
