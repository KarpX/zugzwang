class_name GunfireAudioGenerator
extends RefCounted

## Процедурный синтезатор звуков выстрелов, автоматных очередей и рикошетов
## Создает реалистичные аудиопотоки AudioStreamWAV без внешних файлов зависимостей.

const SAMPLE_RATE: int = 44100

## Создание одиночного резкого выстрела из автоматической винтовки
static func create_gunshot_sound(duration: float = 0.65, bass_intensity: float = 0.85) -> AudioStreamWAV:
	var total_samples: int = int(duration * SAMPLE_RATE)
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(total_samples * 2) # 16-bit mono = 2 bytes per sample
	
	var rand_state: int = 12345
	var prev_noise: float = 0.0
	var lowpass: float = 0.0
	
	for i in range(total_samples):
		var t: float = float(i) / float(SAMPLE_RATE)
		
		# 1. Начальный гипер-резкий транзиент пули (первые 4 мс)
		var crack: float = 0.0
		if t < 0.005:
			crack = sin(t * TAU * 1800.0) * (1.0 - t / 0.005) * 1.5
		
		# 2. Белый/розовый шум взрыва пороха
		rand_state = (rand_state * 1103515245 + 12345) & 0x7FFFFFFF
		var white: float = (float(rand_state) / 1073741824.0) - 1.0
		var noise: float = (prev_noise + (0.05 * white)) / 1.05
		prev_noise = noise
		
		# Экспоненциальный спад шума выстрела
		var noise_env: float = exp(-t * 22.0)
		
		# 3. Низкочастотный глухой удар ствола и эхо в замкнутом пространстве
		var bass: float = sin(t * TAU * (85.0 * exp(-t * 14.0))) * exp(-t * 9.0) * bass_intensity
		
		# 4. Реверберационный хвост железобетонного бункера (затухающие отражения)
		var echo: float = 0.0
		if t > 0.04:
			var echo_env: float = exp(-(t - 0.04) * 6.5) * 0.35
			echo = sin(t * TAU * 340.0) * echo_env * noise
		
		var sample_f: float = (crack * 0.7) + (noise * noise_env * 0.9) + bass + echo
		sample_f = clampf(sample_f, -1.0, 1.0)
		
		var sample_i: int = int(sample_f * 32767.0)
		pcm.encode_s16(i * 2, sample_i)
	
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	return stream

## Создание серии автоматной очереди (3-5 быстрых выстрелов в упор)
static func create_burst_fire_sound(shot_count: int = 4, interval: float = 0.09) -> AudioStreamWAV:
	var total_dur: float = (shot_count - 1) * interval + 0.8
	var total_samples: int = int(total_dur * SAMPLE_RATE)
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(total_samples * 2)
	
	# Буфер сэмплов с плавающей точкой для микширования
	var float_buffer: PackedFloat32Array = PackedFloat32Array()
	float_buffer.resize(total_samples)
	
	var single_shot: AudioStreamWAV = create_gunshot_sound(0.7, 0.9)
	var shot_samples: int = single_shot.data.size() / 2
	
	for shot_idx in range(shot_count):
		var start_sample: int = int(shot_idx * interval * SAMPLE_RATE)
		var shot_vol: float = randf_range(0.85, 1.0)
		
		for s in range(shot_samples):
			var dest_idx: int = start_sample + s
			if dest_idx >= total_samples:
				break
			var raw_sample_i: int = single_shot.data.decode_s16(s * 2)
			var s_float: float = (float(raw_sample_i) / 32768.0) * shot_vol
			float_buffer[dest_idx] += s_float
	
	# Запись в PCM с клиппингом
	for i in range(total_samples):
		var sample_val: float = clampf(float_buffer[i], -1.0, 1.0)
		pcm.encode_s16(i * 2, int(sample_val * 32767.0))
		
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	return stream
