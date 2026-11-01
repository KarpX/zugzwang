extends SceneTree

const ChessLogic = preload("res://scripts/chess/chess_logic.gd")
const ChessBot   = preload("res://scripts/chess/chess_bot.gd")

func _init() -> void:
	var args = OS.get_cmdline_user_args()
	var playthrough: int = 1
	var moves_str: String = ""
	
	for i in range(args.size()):
		if args[i] == "--playthrough" and i + 1 < args.size():
			playthrough = int(args[i + 1])
		elif args[i] == "--moves" and i + 1 < args.size():
			moves_str = args[i + 1]
			
	var logic = ChessLogic.new()
	logic.reset_board(playthrough)
	
	# Применяем ходы UCI ("e2e4,e7e5,...")
	if not moves_str.is_empty():
		for uci in moves_str.split(","):
			uci = uci.strip_edges()
			if uci.length() >= 4:
				var fx = uci.unicode_at(0) - "a".unicode_at(0)
				var fy = int(uci[1]) - 1
				var tx = uci.unicode_at(2) - "a".unicode_at(0)
				var ty = int(uci[3]) - 1
				var promo = "queen"
				if uci.length() >= 5:
					match uci[4]:
						"q": promo = "queen"
						"r": promo = "rook"
						"b": promo = "bishop"
						"n": promo = "knight"
				logic.make_move(Vector2i(fx, fy), Vector2i(tx, ty), promo)
				
	var fen = _board_to_fen(logic)
	
	var white_mat = 0
	var black_mat = 0
	for x in 8:
		for y in 8:
			var p = logic.grid[x][y]
			if p != null and p["type"] != "king":
				var v = ChessBot.PIECE_VALUES[ChessBot.string_to_type(p["type"])]
				if p["is_white"]:
					white_mat += v
				else:
					black_mat += v

	if logic.is_game_over:
		print(JSON.stringify({
			"game_over": true,
			"winner": logic.winner,
			"fen": fen,
			"move": "",
			"material_white": white_mat,
			"material_black": black_mat,
			"material_diff": black_mat - white_mat
		}))
		quit(0)
		return
		
	var move = logic.get_best_ai_move()
	if move.is_empty():
		print(JSON.stringify({
			"game_over": logic.is_game_over,
			"winner": logic.winner if logic.is_game_over else "draw",
			"fen": fen,
			"move": "",
			"material_white": white_mat,
			"material_black": black_mat,
			"material_diff": black_mat - white_mat
		}))
	else:
		var from_sq = char("a".unicode_at(0) + move["from"].x) + str(move["from"].y + 1)
		var to_sq   = char("a".unicode_at(0) + move["to"].x) + str(move["to"].y + 1)
		var uci = from_sq + to_sq
		
		# Проверка превращения пешки
		var promo_type = "queen"
		var p = logic.get_piece(move["from"])
		if p != null and p["type"] == "pawn":
			if (not p["is_white"] and move["to"].y == 0) or (p["is_white"] and move["to"].y == 7):
				uci += "q"
				
		var apply_res = logic.make_move(move["from"], move["to"], promo_type)
		var fen_after = _board_to_fen(logic)
		
		# Пересчет материала после хода бота
		var post_w_mat = 0
		var post_b_mat = 0
		for x in 8:
			for y in 8:
				var piece = logic.grid[x][y]
				if piece != null and piece["type"] != "king":
					var val = ChessBot.PIECE_VALUES[ChessBot.string_to_type(piece["type"])]
					if piece["is_white"]:
						post_w_mat += val
					else:
						post_b_mat += val
				
		print(JSON.stringify({
			"game_over": logic.is_game_over,
			"winner": logic.winner,
			"fen_before": fen,
			"fen_after": fen_after,
			"move": uci,
			"from": from_sq,
			"to": to_sq,
			"material_white": post_w_mat,
			"material_black": post_b_mat,
			"material_diff": post_b_mat - post_w_mat,
			"score": ChessBot.last_search_info.get("score", 0.0),
			"depth": ChessBot.last_search_info.get("depth", 0)
		}))
	quit(0)

func _board_to_fen(logic: ChessLogic) -> String:
	var piece_map := {
		"king":   ["k", "K"],
		"queen":  ["q", "Q"],
		"rook":   ["r", "R"],
		"bishop": ["b", "B"],
		"knight": ["n", "N"],
		"pawn":   ["p", "P"],
	}
	var fen := ""
	for rank in range(7, -1, -1):
		var empty: int = 0
		for file in range(8):
			var piece = logic.grid[file][rank]
			if piece == null:
				empty += 1
			else:
				if empty > 0:
					fen += str(empty)
					empty = 0
				var sym_pair: Array = piece_map.get(piece["type"], ["p", "P"])
				fen += sym_pair[1] if piece["is_white"] else sym_pair[0]
		if empty > 0:
			fen += str(empty)
		if rank > 0:
			fen += "/"

	fen += " " + ("w" if logic.is_white_turn else "b")

	var castling := ""
	var wking = logic.grid[4][0]
	var bking = logic.grid[4][7]
	if wking != null and not wking["has_moved"]:
		var wr = logic.grid[7][0]
		if wr != null and not wr["has_moved"]: castling += "K"
		var wr2 = logic.grid[0][0]
		if wr2 != null and not wr2["has_moved"]: castling += "Q"
	if bking != null and not bking["has_moved"]:
		var br = logic.grid[7][7]
		if br != null and not br["has_moved"]: castling += "k"
		var br2 = logic.grid[0][7]
		if br2 != null and not br2["has_moved"]: castling += "q"
	fen += " " + (castling if not castling.is_empty() else "-")

	var ep = logic.en_passant_target
	var has_ep_capturer = false
	if ep != Vector2i(-1, -1):
		var enemy_pawn_y = ep.y - 1 if logic.is_white_turn else ep.y + 1
		for dx in [-1, 1]:
			var px = ep.x + dx
			if px >= 0 and px < 8 and enemy_pawn_y >= 0 and enemy_pawn_y < 8:
				var piece = logic.grid[px][enemy_pawn_y]
				if piece != null and piece["type"] == "pawn" and piece["is_white"] == logic.is_white_turn:
					has_ep_capturer = true
					break
	if has_ep_capturer:
		var ep_file := char("a".unicode_at(0) + ep.x)
		fen += " " + ep_file + str(ep.y + 1)
	else:
		fen += " -"

	fen += " 0 %d" % (logic.move_count / 2 + 1)
	return fen
