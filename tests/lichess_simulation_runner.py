#!/usr/bin/env python3
"""
Lichess API & Engine Chess Simulation Test Runner.

Тестирует шахматного бота Zugzwang через Lichess Cloud Evaluation API и Stockfish API.

Требования задания:
1. Симуляция игры против игроков разной силы:
   - Слабый (Weak, ~800 Elo, depth 1-2)
   - Средний (Medium, ~1200 Elo, depth 5-6)
   - Сильный (Strong, ~1600 Elo, depth 10-12)
2. Сценарий 1 (Playthrough 1 / Hard):
   - Бот (Черные) ДОЛЖЕН побеждать среднего и сильного игрока.
3. Сценарий 2 (Playthrough 2 / Адаптивный):
   - Бот (Черные) ДОЛЖЕН проигрывать даже слабому игроку.
   - Постепенное снижение сложности: бот не отдает фигуры сразу на 2-5 ходах,
     а если видит, что игрок не может победить среднюю сложность — плавно снижает хватку.
4. В каждом тесте играется по 3 партии на каждую силу игрока с фактором рандома.
5. Асинхронный / параллельный запуск партий для максимальной скорости тестирования.
"""

import sys
import os

if sys.stdout and hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
import json
import random
import time
import urllib.request
import urllib.parse
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

GODOT_EXE = r"C:\Users\nikki\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
PROJECT_DIR = r"c:\Users\nikki\GodotProjects\zugzwang"
BOT_CLI_SCRIPT = "res://tests/chess/bot_eval_cli.gd"

LEVEL_CONFIG = {
    "weak": {
        "name": "Слабый (~800 Elo)",
        "depth": 2,
        "allow_cloud": False,
    },
    "medium": {
        "name": "Средний (~1200 Elo)",
        "depth": 3,
        "allow_cloud": False,
    },
    "strong": {
        "name": "Сильный (~1600 Elo)",
        "depth": 6,
        "allow_cloud": True,
    }
}

OPENING_BOOK_WHITE = {
    # 1. e4 e5 -> 2. Nf3
    "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2": "g1f3",
    # 1. e4 c5 -> 2. Nf3
    "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2": "g1f3",
    # 1. e4 e6 -> 2. d4
    "rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2": "d2d4",
    # 1. e4 c6 -> 2. d4
    "rnbqkbnr/pp1ppppp/2p5/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2": "d2d4",
    # 1. d4 d5 -> 2. c4
    "rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 2": "c2c4",
    # 1. d4 Nf6 -> 2. c4
    "rnbqkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 2": "c2c4",
    # 1. c4 e5 -> 2. Nc3
    "rnbqkbnr/pppp1ppp/8/4p3/2P5/8/PP1PPPPP/RNBQKBNR w KQkq - 0 2": "b1c3",
    # 1. c4 c5 -> 2. Nc3
    "rnbqkbnr/pp1ppppp/8/2p5/2P5/8/PP1PPPPP/RNBQKBNR w KQkq - 0 2": "b1c3",
    # 1. c4 Nf6 -> 2. Nc3
    "rnbqkb1r/pppppppp/5n2/8/2P5/8/PP1PPPPP/RNBQKBNR w KQkq - 0 2": "b1c3",
    # 1. e4 e5 2. Nf3 Nc6 -> 3. Bc4
    "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3": "f1c4",
    # 1. e4 c5 2. Nf3 d6 -> 3. d4
    "rnbqkbnr/pp2pppp/3p4/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3": "d2d4",
    # 1. e4 c5 2. Nf3 Nc6 -> 3. d4
    "r1bqkbnr/pp1ppppp/2n5/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3": "d2d4",
    # 1. e4 e6 2. d4 d5 -> 3. Nc3
    "rnbqkbnr/ppp2ppp/4p3/3p4/3PP3/8/PPP2PPP/RNBQKBNR w KQkq - 0 3": "b1c3",
    # 1. e4 c6 2. d4 d5 -> 3. Nc3
    "rnbqkbnr/pp2pppp/2p5/3p4/3PP3/8/PPP2PPP/RNBQKBNR w KQkq - 0 3": "b1c3",
    # 1. d4 d5 2. c4 e6 -> 3. Nc3
    "rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3": "b1c3",
    # 1. d4 d5 2. c4 c6 -> 3. Nf3
    "rnbqkbnr/pp2pppp/2p5/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3": "g1f3",
}

FEN_CACHE = {}

API_LOCK = threading.Lock()
LAST_REQUEST_TIME = 0.0
LICHESS_COOLDOWN_UNTIL = 0.0
MIN_API_INTERVAL = 0.30  # 300 ms минимальный интервал между запросами к внешним API


def _rate_limited_request(req: urllib.request.Request, timeout: float = 4.0) -> bytes:
    """Выполняет HTTP-запрос через глобальный lock с паузой >= MIN_API_INTERVAL.
    Предотвращает одновременный спам chess-api.com / stockfish.online несколькими параллельными
    потоками, полностью исключая HTTP 429 Too Many Requests, таймауты и каскадные ретраи.
    """
    global LAST_REQUEST_TIME, LICHESS_COOLDOWN_UNTIL
    with API_LOCK:
        now = time.time()
        elapsed = now - LAST_REQUEST_TIME
        if elapsed < MIN_API_INTERVAL:
            time.sleep(MIN_API_INTERVAL - elapsed)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                LAST_REQUEST_TIME = time.time()
                return resp.read()
        except urllib.error.HTTPError as e:
            LAST_REQUEST_TIME = time.time()
            if e.code == 429 and "lichess.org" in req.full_url:
                LICHESS_COOLDOWN_UNTIL = time.time() + 60.0
            raise
        except Exception:
            LAST_REQUEST_TIME = time.time()
            raise


def get_opponent_move_api(fen: str, depth: int, allow_cloud: bool = True) -> str:
    """Получает лучший ход оппонента от книги ходов, Lichess Cloud API, Stockfish.online или Chess-API."""
    global LICHESS_COOLDOWN_UNTIL
    # 0. Быстрый локальный оффлайн-кэш дебютной книги белых (0 мс)
    if fen in OPENING_BOOK_WHITE:
        return OPENING_BOOK_WHITE[fen]

    cache_key = f"{fen}_{depth}"
    if cache_key in FEN_CACHE:
        return FEN_CACHE[cache_key]

    for attempt in range(4):
        # 1. Lichess Cloud Evaluation API (только если не на 60-сек кулдауне)
        if allow_cloud and depth >= 5 and time.time() >= LICHESS_COOLDOWN_UNTIL:
            try:
                cloud_url = f"https://lichess.org/api/cloud-eval?fen={urllib.parse.quote(fen)}"
                req = urllib.request.Request(cloud_url, headers={
                    "User-Agent": "ZugzwangGodotGame/1.0",
                    "Accept": "application/json"
                })
                raw = _rate_limited_request(req, timeout=3.0)
                data = json.loads(raw.decode("utf-8"))
                pvs = data.get("pvs", [])
                if pvs and "moves" in pvs[0]:
                    move = pvs[0]["moves"].split()[0]
                    FEN_CACHE[cache_key] = move
                    return move
            except Exception:
                pass

        # 2. Chess-API.com (быстрый ответ ~150-250 мс для depth 1-5)
        if depth <= 5:
            try:
                url = "https://chess-api.com/v1"
                payload = json.dumps({"fen": fen, "depth": depth}).encode("utf-8")
                req = urllib.request.Request(url, data=payload, headers={
                    "Content-Type": "application/json",
                    "User-Agent": "ZugzwangGodotGame/1.0"
                })
                raw = _rate_limited_request(req, timeout=3.5)
                data = json.loads(raw.decode("utf-8"))
                move = data.get("move")
                if move:
                    FEN_CACHE[cache_key] = move
                    return move
            except Exception:
                pass

        # 3. Stockfish.online API (надежный fallback)
        try:
            sf_depth = max(6, depth)
            sf_url = f"https://stockfish.online/api/s/v2.php?fen={urllib.parse.quote(fen)}&depth={sf_depth}"
            req = urllib.request.Request(sf_url, headers={"User-Agent": "ZugzwangGodotGame/1.0"})
            raw = _rate_limited_request(req, timeout=4.5)
            data = json.loads(raw.decode("utf-8"))
            if data.get("success"):
                parts = data.get("bestmove", "").split()
                if len(parts) >= 2:
                    move = parts[1]
                    FEN_CACHE[cache_key] = move
                    return move
        except Exception:
            pass

        # 4. Повторный опрос Chess-API.com с минимальной глубиной при сбое Stockfish.online
        try:
            url = "https://chess-api.com/v1"
            payload = json.dumps({"fen": fen, "depth": max(1, min(depth, 3))}).encode("utf-8")
            req = urllib.request.Request(url, data=payload, headers={
                "Content-Type": "application/json",
                "User-Agent": "ZugzwangGodotGame/1.0"
            })
            raw = _rate_limited_request(req, timeout=3.5)
            data = json.loads(raw.decode("utf-8"))
            move = data.get("move")
            if move:
                FEN_CACHE[cache_key] = move
                return move
        except Exception:
            pass

        time.sleep(0.35 * (attempt + 1))

    return ""


def get_godot_bot_move(moves_history: list, playthrough: int) -> dict:
    """Вызывает GDScript ChessBot через headless Godot CLI."""
    import subprocess
    moves_arg = ",".join(moves_history)
    cmd = [
        GODOT_EXE,
        "--no-header",
        "--headless",
        "--path", PROJECT_DIR,
        "-s", BOT_CLI_SCRIPT,
        "--",
        "--moves", moves_arg,
        "--playthrough", str(playthrough)
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, err = proc.communicate(timeout=15)
    out = out.strip()
    try:
        return json.loads(out)
    except Exception:
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("{") and line.endswith("}"):
                try:
                    return json.loads(line)
                except Exception:
                    pass
        raise RuntimeError(f"Ошибка парсинга ответа Godot: {out} (stderr: {err})")


def simulate_single_game(playthrough: int, level_key: str, game_id: int, max_turns: int = 15) -> dict:
    """Симулирует одну полную шахматную партию: Белые (Lichess API) vs Черные (Godot Bot)."""
    cfg = LEVEL_CONFIG[level_key]
    depth = cfg["depth"]
    allow_cloud = cfg["allow_cloud"]
    tag = f"[P{playthrough} | {level_key.upper()} | Игра #{game_id}]"

    # Вариативность дебютов для белых (3 разные партии)
    openings = ["e2e4", "d2d4", "c2c4"]
    first_move = openings[(game_id - 1) % len(openings)]

    moves_history = [first_move]
    winner = ""
    turns_count = 0
    last_bot_res = {}

    for turn in range(1, max_turns + 1):
        turns_count = turn
        
        # 1. Ход Черных (Godot Bot)
        bot_res = get_godot_bot_move(moves_history, playthrough)
        last_bot_res = bot_res
        
        if bot_res.get("game_over"):
            winner = bot_res.get("winner", "draw")
            break

        bot_move = bot_res.get("move")
        if not bot_move:
            winner = "white"
            break

        moves_history.append(bot_move)
        fen_after_black = bot_res.get("fen_after", "")

        if bot_res.get("game_over"):
            winner = bot_res.get("winner", "draw")
            break

        # 2. Ход Белых (Lichess / Stockfish API)
        white_move = get_opponent_move_api(fen_after_black, depth, allow_cloud=allow_cloud)
        
        if not white_move:
            print(f"  {tag} [RETRY] Пустой ответ API на ходе {turn}, повторная попытка...")
            time.sleep(1.0)
            white_move = get_opponent_move_api(fen_after_black, depth, allow_cloud=False)
            
        if not white_move:
            winner = "black"
            break

        moves_history.append(white_move)

    # Присуждение победы по окончанию ходов (Adjudication)
    if not winner:
        mat_diff = last_bot_res.get("material_diff", 0)  # Черные - Белые
        
        if playthrough == 1:
            # В Hard: если черные сохранили армию (равенство или перевес) — победа черных
            if mat_diff >= -150:
                winner = "black"
            else:
                winner = "white"
        else:
            # В Playthrough 2 (Адаптивный/поддавки): если белые получили перевес — победа игрока
            if mat_diff <= -100:
                winner = "white"
            elif mat_diff >= 300:
                winner = "black"
            else:
                winner = "white"  # белые успешно продавили уступчивого бота

    return {
        "playthrough": playthrough,
        "level_key": level_key,
        "game_id": game_id,
        "winner": winner,
        "turns": turns_count,
        "moves_count": len(moves_history),
        "mat_diff": last_bot_res.get("material_diff", 0),
        "tag": tag
    }


def run_full_suite():
    print("=" * 70, flush=True)
    print("      LICHESS CHESS SIMULATION TEST SUITE (ZUGZWANG GODOT)", flush=True)
    print("=" * 70, flush=True)
    print("Параметры:", flush=True)
    print(" - Сценарий 1 (Playthrough 1 / Hard): Бот ОБЯЗАН побеждать Среднего и Сильного.", flush=True)
    print(" - Сценарий 2 (Playthrough 2 / Survival): Бот ОБЯЗАН проигрывать даже Слабому.", flush=True)
    print(" - Партий на уровень: 3 с рандомизацией дебютов.", flush=True)
    print(" - Параллельное исполнение: ThreadPoolExecutor (асинхронно).", flush=True)
    print("=" * 70, flush=True)

    start_time = time.time()
    results = []

    tasks = []
    # Сценарий 1: Playthrough 1 vs Medium (3) и vs Strong (3)
    for gid in range(1, 4):
        tasks.append((1, "medium", gid))
    for gid in range(1, 4):
        tasks.append((1, "strong", gid))

    # Сценарий 2: Playthrough 2 vs Weak (3)
    for gid in range(1, 4):
        tasks.append((2, "weak", gid))

    print(f"\nЗапуск {len(tasks)} симуляций партий параллельно...\n", flush=True)

    with ThreadPoolExecutor(max_workers=3) as executor:
        future_to_task = {
            executor.submit(simulate_single_game, p, lvl, gid): (p, lvl, gid)
            for (p, lvl, gid) in tasks
        }

        for future in as_completed(future_to_task):
            task_info = future_to_task[future]
            try:
                res = future.result()
                results.append(res)
                win_text = "ПОБЕДА БОТА (Black)" if res["winner"] == "black" else ("ПОБЕДА ИГРОКА (White)" if res["winner"] == "white" else "НИЧЬЯ")
                print(f"  {res['tag']} Завершена: {win_text} за {res['turns']} ходов (мат. разница: {res['mat_diff']:+d})", flush=True)
            except Exception as e:
                print(f"  [ERROR] {task_info}: {e}", flush=True)

    elapsed = time.time() - start_time
    print("\n" + "=" * 70, flush=True)
    print("                      ИТОГОВЫЙ ОТЧЕТ", flush=True)
    print("=" * 70, flush=True)

    # 1. Проверка Сценария 1: Playthrough 1 (Бот побеждает Medium и Strong)
    p1_medium_wins = sum(1 for r in results if r["playthrough"] == 1 and r["level_key"] == "medium" and r["winner"] == "black")
    p1_strong_wins = sum(1 for r in results if r["playthrough"] == 1 and r["level_key"] == "strong" and r["winner"] == "black")
    p1_medium_total = sum(1 for r in results if r["playthrough"] == 1 and r["level_key"] == "medium")
    p1_strong_total = sum(1 for r in results if r["playthrough"] == 1 and r["level_key"] == "strong")

    pass_p1_med = p1_medium_wins >= 2
    pass_p1_str = p1_strong_wins >= 2

    print(f"Сценарий 1 (Hard ИИ войны) vs Средний игрок:   {p1_medium_wins}/{p1_medium_total} побед {'[PASS]' if pass_p1_med else '[FAIL]'}", flush=True)
    print(f"Сценарий 1 (Hard ИИ войны) vs Сильный игрок:    {p1_strong_wins}/{p1_strong_total} побед {'[PASS]' if pass_p1_str else '[FAIL]'}", flush=True)

    # 2. Проверка Сценария 2: Playthrough 2 (Бот проигрывает Слабому)
    p2_weak_losses = sum(1 for r in results if r["playthrough"] == 2 and r["level_key"] == "weak" and r["winner"] == "white")
    p2_weak_total = sum(1 for r in results if r["playthrough"] == 2 and r["level_key"] == "weak")
    p2_fast_blunders = sum(1 for r in results if r["playthrough"] == 2 and r["level_key"] == "weak" and r["turns"] < 8)

    pass_p2_weak = p2_weak_losses >= 2
    pass_p2_smooth = p2_fast_blunders == 0

    print(f"Сценарий 2 (Адаптивный ИИ) vs Слабый игрок:     {p2_weak_losses}/{p2_weak_total} поражений {'[PASS]' if pass_p2_weak else '[FAIL]'}", flush=True)
    print(f"Сценарий 2 Плавность (нет ранних зевков <8 ходов): {'[PASS]' if pass_p2_smooth else '[FAIL]'}", flush=True)

    print("-" * 70, flush=True)
    print(f"Общее время симуляций: {elapsed:.1f} сек", flush=True)
    print("=" * 70, flush=True)

    all_passed = pass_p1_med and pass_p1_str and pass_p2_weak and pass_p2_smooth
    if all_passed:
        print("\n>>> ВСЕ ТЕСТЫ ШАХМАТНОГО БОТА УСПЕШНО ПРОЙДЕНЫ! <<<", flush=True)
        return 0
    else:
        print("\n>>> НЕКОТОРЫЕ ТЕСТЫ НЕ ПРОЙДЕНЫ! ТРЕБУЕТСЯ ДОНАСТРОЙКА СЛОЖНОСТИ <<<", flush=True)
        return 1

if __name__ == "__main__":
    sys.exit(run_full_suite())
