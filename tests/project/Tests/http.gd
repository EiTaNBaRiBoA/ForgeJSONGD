## A real HTTP round trip: an HTTPRequest posts a DTO to a small server running in this scene,
## and reads the answers. The server records the exact request text it received.
extends Node

const PORT = 18765

var _server: TCPServer = TCPServer.new()
var _clients: Array[StreamPeerTCP] = []
var _buffers: Dictionary = {}
var _requests: Array[Dictionary] = [] # what the server received: method, path, headers, body
var _routes: Dictionary = {} # "METHOD /path" -> response body text
var _http: HTTPRequest
var _done: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	if _server.listen(PORT, "127.0.0.1") != OK:
		TestUtil.check(false, "the test server can listen on port %d" % PORT)
		_finish()
		return
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		if not _done:
			TestUtil.check(false, "the HTTP test finished in time")
			_finish())
	await _run()
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_server.stop()
	TestUtil.finish("Http", get_tree())


func _run() -> void:
	var login: LoginDto = LoginDto.new()
	login.user_name = "ann"
	login.password = "pw"
	login.remember = true
	login.attempts = 2

	# What a real server sends back: nulls, numbers where text is expected, extra fields, ids as text.
	_routes["POST /login"] = '{"id":42,"userName":"ann","score":3,"tags":["a"],"bigId":"9007199254740993","nickname":null,"isAdmin":null,"unknown":{"x":1},"address":{"city":"Tokyo","zip":100},"role":"Admin","position":{"x":5,"y":6},"meta":{"count":5,"ratio":2.0,"1":"one","text":"Vector2(1, 2)"}}'
	var reply: Dictionary = await _call(HTTPClient.METHOD_POST, "/login", ForgeJSONGD.class_to_json_string(login))
	var seen: Dictionary = _requests.back()
	TestUtil.check(reply.code == 200 and seen.method == "POST" and seen.path == "/login", "the request reached the server")
	TestUtil.check(seen.body == '{"attempts":2,"password":"pw","remember":true,"userName":"ann"}', "the server received exactly the expected JSON text")
	TestUtil.check(String(seen.headers.get("content-type", "")).begins_with("application/json"), "the server saw the JSON content type")
	var user: UserDto = ForgeJSONGD.json_string_to_class(UserDto, reply.text)
	TestUtil.check(user.id == 42 and user.user_name == "ann" and user.score == 3.0 and user.tags == ["a"], "the response is read into a DTO")
	TestUtil.check(user.big_id == 9007199254740993 and user.nickname == "none", "an id sent as text is exact, and a null keeps the default")
	TestUtil.check(user.address.city == "Tokyo" and user.address.zip == "100" and user.role == UserDto.Role.ADMIN and user.position == Vector2(5, 6), "nested object, number-as-text, enum and vector are read")
	TestUtil.check(user.meta == {"count": 5, "ratio": 2, "1": "one", "text": "Vector2(1, 2)"}, "free-form data is read as the server sent it")

	# A big DTO goes out and comes back through the server unchanged.
	var original: UserDto = UserDto.new()
	original.id = 7
	original.user_name = "ann"
	original.score = 2.0
	original.tags = ["a", "b"]
	original.address = AddressDto.new()
	original.address.city = "Tokyo"
	original.address.zip = "100"
	original.meta = {"count": 5, "ratio": 2.0, "1": "one", "true": "t", "text": "Vector2(1, 2)", "forge_text:x": "y"}
	original.position = Vector2(1, 2)
	original.color = Color.RED
	original.role = UserDto.Role.ADMIN
	original.big_id = 9007199254740993
	original.secret = "never sent"
	var body: String = ForgeJSONGD.class_to_json_string(original)
	_routes["POST /echo"] = body
	var echo: Dictionary = await _call(HTTPClient.METHOD_POST, "/echo", body)
	var sent: String = _requests.back().body
	TestUtil.check(sent == body and not sent.contains("forge_float") and not sent.contains("script_") and not sent.contains("never sent"), "the whole DTO was sent as plain JSON")
	TestUtil.check(sent.contains('"bigId":9007199254740993') and sent.contains('"userName":"ann"') and sent.contains('"position":{"x":1.0,"y":2.0}'), "keys, big ids and vectors are in the API format")
	var back: UserDto = ForgeJSONGD.json_string_to_class(UserDto, echo.text)
	TestUtil.check(back.user_name == "ann" and back.address.city == "Tokyo" and back.color == Color.RED and back.role == UserDto.Role.ADMIN and back.position == Vector2(1, 2), "the answer is read into an equal DTO")
	TestUtil.check(back.meta["forge_text:x"] == "y" and back.meta["true"] == "t" and back.meta["text"] == "Vector2(1, 2)" and typeof(back.meta["count"]) == TYPE_INT, "free-form data survived the trip")
	TestUtil.check(back.secret == "", "an excluded variable is not sent")

	# A server that tries to make the client create classes or load files.
	_routes["GET /hostile"] = '{"id":1,"script_inheritance":"res://Tests/Models/PlainScript.gd","script_constructor_args":[1],"address":{"city":"Z","script_inheritance":"Dog"},"friends":[{"id":2,"script_inheritance":"Cat"}],"meta":{"r":{"forge_resource_path":"res://icon.svg"},"p":"res://icon.svg"}}'
	var hostile: Dictionary = await _call(HTTPClient.METHOD_GET, "/hostile", "")
	var safe: UserDto = ForgeJSONGD.json_string_to_class(UserDto, hostile.text)
	TestUtil.check(safe is UserDto and safe.id == 1 and safe.address is AddressDto and safe.friends[0] is UserDto, "class names sent by a server are ignored")
	TestUtil.check(safe.meta["r"] is Dictionary and safe.meta["p"] == "res://icon.svg", "paths and markers sent by a server stay plain data")

	# Documented limit of Godot's JSON parser: a JSON number above 2^53 is read as a double.
	_routes["GET /bigid"] = '{"id":9007199254740993,"bigId":9007199254740993}'
	var big: Dictionary = await _call(HTTPClient.METHOD_GET, "/bigid", "")
	var big_user: UserDto = ForgeJSONGD.json_string_to_class(UserDto, big.text)
	TestUtil.check(big_user.id == 9007199254740992, "a JSON number above 2^53 is read with the precision of Godot's parser (servers should send such ids as text)")


# Sends a request and waits for the answer.
func _call(method: HTTPClient.Method, path: String, body: String) -> Dictionary:
	var error: Error = _http.request("http://127.0.0.1:%d%s" % [PORT, path], ["Content-Type: application/json"], method, body)
	if error != OK:
		TestUtil.check(false, "the request could be started (%s)" % error_string(error))
		return {"code": 0, "text": ""}
	var answer: Array = await _http.request_completed
	return {"code": answer[1], "text": (answer[3] as PackedByteArray).get_string_from_utf8()}


func _process(_delta: float) -> void:
	if _server.is_connection_available():
		_clients.append(_server.take_connection())
	for client: StreamPeerTCP in _clients.duplicate():
		client.poll()
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(client)
			_buffers.erase(client)
			continue
		var available: int = client.get_available_bytes()
		if available > 0:
			var chunk: Array = client.get_data(available)
			var data: PackedByteArray = _buffers.get(client, PackedByteArray())
			data.append_array(chunk[1])
			_buffers[client] = data
			_try_answer(client, data)


# Answers once the whole request (headers and body) has arrived.
func _try_answer(client: StreamPeerTCP, data: PackedByteArray) -> void:
	var text: String = data.get_string_from_utf8()
	var header_end: int = text.find("\r\n\r\n")
	if header_end == -1:
		return
	var head: PackedStringArray = text.substr(0, header_end).split("\r\n")
	var headers: Dictionary = {}
	for line_index: int in range(1, head.size()):
		var parts: PackedStringArray = head[line_index].split(":", true, 1)
		if parts.size() == 2:
			headers[parts[0].strip_edges().to_lower()] = parts[1].strip_edges()
	var length: int = int(headers.get("content-length", "0"))
	var body_bytes: PackedByteArray = data.slice(text.substr(0, header_end + 4).to_utf8_buffer().size())
	if body_bytes.size() < length:
		return
	var request_line: PackedStringArray = head[0].split(" ")
	_requests.append({"method": request_line[0], "path": request_line[1], "headers": headers, "body": body_bytes.get_string_from_utf8()})
	var answer: String = _routes.get("%s %s" % [request_line[0], request_line[1]], "{}")
	var answer_bytes: PackedByteArray = answer.to_utf8_buffer()
	var response: String = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % answer_bytes.size()
	client.put_data(response.to_utf8_buffer())
	client.put_data(answer_bytes)
	client.disconnect_from_host()
	_clients.erase(client)
	_buffers.erase(client)
