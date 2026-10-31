class_name OutsideAudioGenerator
extends RefCounted

## Процедурный генератор высококачественных аудиосэмплов для внешнего мира войны (Outside War SFX)
## Генерирует звуки артиллерии, разрывов, свиста снарядов, сирен и инфразвукового гула
## Работает в памяти за миллисекунды без внешних зависимостей.

const SAMPLE_RATE: int = 22050

## Генерация далекого артиллерийского разрыва (Пешка: глухой boom за 3-5 км с долгим эхом)
static func create_distant_boom() -> AudioStreamWAV:
	var duration: float = 2.4
	var total_samples: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	
	var noise_val: float = 0.0
	for i in range(total_samples):
		var t: float = float(i) / SAMPLE_RATE
		# Экспоненциальный спад
		var env: float = exp(-1.8 * t) * (1.0 - exp(-30.0 * t))
		# Низкочастотный рокот (45-80 Гц)
		var sub_bass: float = sin(TAU * 52.0 * t) * 0.65 + sin(TAU * 78.0 * t) * 0.35
		# Коричневый шум (интегратор белого шума)
		var white: float = randf_range(-1.0, 1.0)
		noise_val = clampf(noise_val * 0.94 + white * 0.06, -1.0, 1.0)
		
		var sample: float = (sub_bass * 0.55 + noise_val * 0.45) * env
		data.encode_s16(i * 2, clampi(int(sample * 32760.0), -32767, 32767))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

## Генерация пикирующего снаряда и удара (Конь: свист ракеты 850->320 Гц + сдвоенный глухой удар)
static func create_missile_whistle_impact() -> AudioStreamWAV:
	var duration: float = 2.0
	var total_samples: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	
	var whistle_phase: float = 0.0
	var noise_acc: float = 0.0
	for i in range(total_samples):
		var t: float = float(i) / SAMPLE_RATE
		var sample: float = 0.0
		
		# Первая фаза (0.0..0.7с): Нарастающий свист падающего снаряда
		if t < 0.72:
			var norm_t: float = t / 0.72
			var freq: float = lerpf(860.0, 310.0, norm_t * norm_t)
			whistle_phase += TAU * freq / SAMPLE_RATE
			var whistle_env: float = norm_t * norm_t * 0.75
			var whistle_tone: float = sin(whistle_phase) + sin(whistle_phase * 1.5) * 0.25
			sample += whistle_tone * whistle_env
		
		# Вторая фаза (0.68..2.0с): Сдвоенный глухой удар
		if t >= 0.68:
			var t_hit1: float = t - 0.68
			var env1: float = exp(-4.0 * t_hit1) * (1.0 - exp(-60.0 * t_hit1))
			var hit1: float = sin(TAU * 68.0 * t_hit1) * env1
			
			var t_hit2: float = t - 0.88
			var hit2: float = 0.0
			if t_hit2 >= 0.0:
				var env2: float = exp(-3.2 * t_hit2) * (1.0 - exp(-50.0 * t_hit2))
				hit2 = (sin(TAU * 55.0 * t_hit2) + sin(TAU * 110.0 * t_hit2) * 0.4) * env2
				
			noise_acc = clampf(noise_acc * 0.92 + randf_range(-1.0, 1.0) * 0.08, -1.0, 1.0)
			sample += (hit1 * 0.7 + hit2 * 0.8 + noise_acc * 0.3 * env1)
			
		data.encode_s16(i * 2, clampi(int(clampf(sample, -1.0, 1.0) * 32760.0), -32767, 32767))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

## Генерация залпа тяжелой батареи (Слон: 3 быстрых глухих раската + скрежет металла)
static func create_artillery_salvo() -> AudioStreamWAV:
	var duration: float = 2.6
	var total_samples: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	
	var shot_times: Array[float] = [0.0, 0.34, 0.72]
	var shot_freqs: Array[float] = [72.0, 64.0, 56.0]
	var noise_filter: float = 0.0
	
	for i in range(total_samples):
		var t: float = float(i) / SAMPLE_RATE
		var sample: float = 0.0
		
		for s in range(shot_times.size()):
			var st: float = t - shot_times[s]
			if st >= 0.0:
				var env: float = exp(-3.5 * st) * (1.0 - exp(-70.0 * st))
				var bass: float = sin(TAU * shot_freqs[s] * st) * 0.75
				sample += bass * env
				
		# Добавляем резонансный металлический скрежет
		if t >= 0.8:
			var mt: float = t - 0.8
			var metal_env: float = exp(-2.2 * mt) * 0.35
			sample += sin(TAU * 240.0 * mt + sin(TAU * 18.0 * mt) * 2.0) * metal_env
			
		noise_filter = clampf(noise_filter * 0.93 + randf_range(-1.0, 1.0) * 0.07, -1.0, 1.0)
		sample += noise_filter * exp(-1.5 * t) * 0.25
		
		data.encode_s16(i * 2, clampi(int(clampf(sample, -1.0, 1.0) * 32760.0), -32767, 32767))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

## Генерация колоссального взрыва укрепления (Ладья: мощный разрыв у бункера, грохот плит)
static func create_massive_fortress_blast() -> AudioStreamWAV:
	var duration: float = 3.2
	var total_samples: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	
	var noise_low: float = 0.0
	var noise_high: float = 0.0
	for i in range(total_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-1.4 * t) * (1.0 - exp(-90.0 * t))
		
		# Двойной суб-басовый удар
		var sub: float = (sin(TAU * 42.0 * t) * 0.7 + sin(TAU * 84.0 * t) * 0.3) * env
		
		var w: float = randf_range(-1.0, 1.0)
		noise_low = clampf(noise_low * 0.91 + w * 0.09, -1.0, 1.0)
		noise_high = clampf(noise_high * 0.65 + w * 0.35, -1.0, 1.0)
		
		# Свист осколков и шуршание осыпающегося бетона
		var debris: float = noise_high * exp(-2.5 * t) * 0.28
		
		var sample: float = sub * 0.65 + noise_low * env * 0.55 + debris
		data.encode_s16(i * 2, clampi(int(clampf(sample, -1.0, 1.0) * 32760.0), -32767, 32767))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

## Генерация стратегического инфразвукового удара (Ферзь: монолитный гул 35-50 Гц + ураганная волна)
static func create_sub_bass_nuke_drone() -> AudioStreamWAV:
	var duration: float = 4.2
	var total_samples: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	
	var noise_wind: float = 0.0
	for i in range(total_samples):
		var t: float = float(i) / SAMPLE_RATE
		# Медленное грозное нарастание (1.2с) и затем затяжной рокот
		var attack: float = smoothstep(0.0, 1.2, t)
		var decay: float = exp(-0.6 * maxf(0.0, t - 1.2))
		var env: float = attack * decay
		
		# Инфразвуковая синусоида со свипом 36 -> 48 -> 34 Гц
		var f: float = 38.0 + sin(t * 1.5) * 8.0
		var sub: float = sin(TAU * f * t) * 0.75 + sin(TAU * (f * 0.5) * t) * 0.4
		
		var w: float = randf_range(-1.0, 1.0)
		noise_wind = clampf(noise_wind * 0.94 + w * 0.06, -1.0, 1.0)
		var wind: float = noise_wind * (1.0 + sin(t * 4.0) * 0.3)
		
		var sample: float = (sub * 0.7 + wind * 0.4) * env
		data.encode_s16(i * 2, clampi(int(clampf(sample, -1.0, 1.0) * 32760.0), -32767, 32767))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

## Фоновый рокот фронта (Стадия I: зацикленный инфразвуковой гул 38 Гц)
static func create_front_rumble_loop() -> AudioStreamWAV:
	var duration: float = 3.0
	var total_samples: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	
	var noise_rumble: float = 0.0
	for i in range(total_samples):
		var t: float = float(i) / SAMPLE_RATE
		var sub1: float = sin(TAU * 38.0 * t) * 0.45
		var sub2: float = sin(TAU * 57.0 * t) * 0.30
		
		var w: float = randf_range(-1.0, 1.0)
		noise_rumble = clampf(noise_rumble * 0.95 + w * 0.05, -1.0, 1.0)
		
		# Обеспечиваем плавный crossfade на концах для идеального зацикливания
		var loop_fade: float = sin(PI * t / duration)
		var sample: float = (sub1 + sub2 + noise_rumble * 0.4) * (0.7 + 0.3 * loop_fade)
		data.encode_s16(i * 2, clampi(int(clampf(sample * 0.5, -1.0, 1.0) * 32760.0), -32767, 32767))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = data
	return stream

## Сирена воздушной тревоги за стенами (Стадия II: зацикленный двухтональный вой 460-620 Гц)
static func create_air_raid_siren_loop() -> AudioStreamWAV:
	var duration: float = 4.0
	var total_samples: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	
	var siren_phase: float = 0.0
	for i in range(total_samples):
		var t: float = float(i) / SAMPLE_RATE
		# Частотная модуляция: 1 полный цикл сирены ровно за 4 секунды (TAU * 0.25 * t)
		var mod: float = sin(TAU * 0.25 * t) # -1 .. +1
		var current_freq: float = 540.0 + mod * 120.0
		
		siren_phase += TAU * current_freq / SAMPLE_RATE
		# Добавляем характерные гармоники металлического рупора
		var sample: float = sin(siren_phase) * 0.65 + sin(siren_phase * 2.0) * 0.25 + sin(siren_phase * 3.0) * 0.10
		
		data.encode_s16(i * 2, clampi(int(clampf(sample * 0.45, -1.0, 1.0) * 32760.0), -32767, 32767))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = data
	return stream

## Вой ураганного пепельного ветра (Стадия III: зацикленный белый/коричневый шум ветра)
static func create_storm_wind_loop() -> AudioStreamWAV:
	var duration: float = 3.5
	var total_samples: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	
	var wind_filter1: float = 0.0
	var wind_filter2: float = 0.0
	for i in range(total_samples):
		var t: float = float(i) / SAMPLE_RATE
		var w: float = randf_range(-1.0, 1.0)
		wind_filter1 = clampf(wind_filter1 * 0.93 + w * 0.07, -1.0, 1.0)
		wind_filter2 = clampf(wind_filter2 * 0.85 + w * 0.15, -1.0, 1.0)
		
		var gust: float = 0.7 + 0.3 * sin(TAU * 0.4 * t)
		var sample: float = (wind_filter1 * 0.7 + wind_filter2 * 0.3) * gust
		
		data.encode_s16(i * 2, clampi(int(clampf(sample * 0.4, -1.0, 1.0) * 32760.0), -32767, 32767))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = data
	return stream

## Монотонный зуммер номерной радиостанции типа УВБ-76 (Стадия III в радио)
static func create_radio_uvb76_buzzer() -> AudioStreamWAV:
	var duration: float = 2.0
	var total_samples: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t: float = float(i) / SAMPLE_RATE
		# 2 гудка за 2 секунды (вспышка 0.0..0.15с и 1.0..1.15с)
		var in_buzz: bool = (t >= 0.05 and t <= 0.22) or (t >= 1.05 and t <= 1.22)
		var sample: float = 0.0
		if in_buzz:
			# Характерный хриплый жужжащий тон (50 Гц сетевой фон + 460 Гц гармоника)
			sample = sin(TAU * 460.0 * t) * 0.6 + sin(TAU * 50.0 * t) * 0.3 + randf_range(-0.1, 0.1)
		else:
			# Слабое шипение белого шума эфира
			sample = randf_range(-0.04, 0.04)
			
		data.encode_s16(i * 2, clampi(int(clampf(sample * 0.4, -1.0, 1.0) * 32760.0), -32767, 32767))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = data
	return stream
