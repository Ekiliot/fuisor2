import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class VoiceRecorderController {
  _VoiceRecorderWidgetState? _state;

  void _attach(_VoiceRecorderWidgetState state) {
    _state = state;
  }

  void _detach(_VoiceRecorderWidgetState state) {
    if (_state == state) {
      _state = null;
    }
  }

  Future<void> stopAndSendImmediate() async {
    if (_state != null) {
      await _state!.stopAndSendImmediate();
    }
  }

  Future<void> stopRecording() async {
    if (_state != null) {
      await _state!.stopRecording();
    }
  }

  Future<void> cancelRecording() async {
    if (_state != null) {
      await _state!.cancelRecording();
    }
  }

  void lockRecording() {
    _state?.lockRecording();
  }

  bool get isLocked => _state?._isLocked ?? false;
  bool get isRecording => _state?._isRecording ?? false;
  bool get isStopped => _state?._isStopped ?? false;
  String? get stoppedPath => _state?._stoppedPath;
  int get stoppedDuration => _state?._stoppedDuration ?? 0;
}

class VoiceRecorderWidget extends StatefulWidget {
  final Function(String path, int duration) onSend;
  final VoidCallback onCancel;
  final Function(String path, int duration)? onStop; // Остановка без отправки (для переслушивания)
  final VoiceRecorderController? controller;

  const VoiceRecorderWidget({
    super.key,
    required this.onSend,
    required this.onCancel,
    this.onStop, // Опциональный callback для остановки
    this.controller,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isLocked = false;
  bool _isStopped = false; // Запись остановлена, но не отправлена (для переслушивания)
  int _recordDuration = 0;
  Timer? _timer;
  Timer? _amplitudeTimer;
  List<double> _amplitudes = List.generate(40, (_) => 0.0, growable: true);
  double _currentAmplitude = 0.0;
  String? _currentPath;
  String? _stoppedPath; // Путь к остановленному файлу
  int _stoppedDuration = 0; // Длительность остановленной записи

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startRecording();
    });
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    
    // Останавливаем таймеры
    _timer?.cancel();
    _timer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    
    // Останавливаем запись, если она активна
    if (_isRecording) {
      _audioRecorder.stop().catchError((e) {
        print('VoiceRecorderWidget: Error stopping in dispose: $e');
        return null;
      });
    }
    
    // Освобождаем ресурсы микрофона
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VoiceRecorderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!mounted) return;
      
      if (await _audioRecorder.hasPermission()) {
        final path = await _getAudioPath();
        if (!mounted) return;
        
        _currentPath = path;
        final startTime = DateTime.now();
        print('🎤 [VoiceRecorder] Начало записи - путь: $path, время: ${startTime.toIso8601String()}');
        await _audioRecorder.start(const RecordConfig(), path: path);
        
        if (!mounted) return;

        setState(() {
          _isRecording = true;
          _isLocked = false;
          _recordDuration = 0;
          _amplitudes = List.generate(40, (_) => 0.0, growable: true);
        });
        print('🎤 [VoiceRecorder] Запись начата успешно');

        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted || !_isRecording) {
            timer.cancel();
            return;
          }
          setState(() {
            _recordDuration++;
          });
        });

        _amplitudeTimer?.cancel();
        _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
          // Проверяем, что запись все еще активна перед получением амплитуды
          if (!_isRecording || !mounted) {
            timer.cancel();
            return;
          }
          try {
            final isCurrentlyRecording = await _audioRecorder.isRecording();
            if (!isCurrentlyRecording || !mounted) {
              timer.cancel();
              return;
            }
            final amplitude = await _audioRecorder.getAmplitude();
            if (mounted) {
              setState(() {
                _currentAmplitude = (amplitude.current + 60) / 60;
                _amplitudes = [..._amplitudes.sublist(1), _currentAmplitude.clamp(0.0, 1.0)];
              });
            }
          } catch (e) {
            // Если ошибка при получении амплитуды, останавливаем таймер
            print('VoiceRecorderWidget: Error getting amplitude: $e');
            timer.cancel();
          }
        });
      } else {
        print('VoiceRecorderWidget: Permission denied');
        if (mounted) {
          widget.onCancel();
        }
      }
    } catch (e) {
      print('VoiceRecorderWidget: Error starting recording: $e');
      if (mounted) {
        widget.onCancel();
      }
    }
  }

  Future<String> _getAudioPath() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'voice_$timestamp.m4a';
    
    // На мобильных устройствах используем правильный путь через path_provider
    if (!kIsWeb) {
      try {
        final tempDir = await getTemporaryDirectory();
        return '${tempDir.path}/$fileName';
      } catch (e) {
        print('VoiceRecorderWidget: Error getting temp directory: $e');
        // Fallback на десктопный путь, если path_provider не работает
        return '/tmp/$fileName';
      }
    }
    
    // Для веб-платформы
    return '/tmp/$fileName';
  }

  /// Отправить немедленно (для обычного режима - отпустил кнопку)
  Future<void> stopAndSendImmediate() async {
    await _stopRecording(send: true);
  }

  /// Заблокировать запись (режим свободных рук)
  void lockRecording() {
    if (!_isLocked && _isRecording) {
      setState(() {
        _isLocked = true;
      });
      print('VoiceRecorderWidget: Recording locked (hands-free mode)');
    }
  }

  /// Отменить запись
  Future<void> cancelRecording() async {
    try {
      // Сначала останавливаем таймеры, чтобы не было попыток получить амплитуду
      _timer?.cancel();
      _timer = null;
      _amplitudeTimer?.cancel();
      _amplitudeTimer = null;
      
      // Затем останавливаем запись
      if (_isRecording) {
        try {
          final isCurrentlyRecording = await _audioRecorder.isRecording();
          if (isCurrentlyRecording) {
            await _audioRecorder.stop();
          }
        } catch (e) {
          print('VoiceRecorderWidget: Error stopping recorder in cancel: $e');
        }
      }
    } catch (e) {
      print('VoiceRecorderWidget: Error cancelling recording: $e');
    }
    _resetState();
    widget.onCancel();
  }

  /// Остановить запись без отправки (для переслушивания)
  Future<void> stopRecording() async {
    // Сразу обновляем UI для быстрой реакции
    if (mounted) {
      setState(() {
        _isStopped = true;
        _isRecording = false;
      });
    }
    // Затем останавливаем запись асинхронно
    _stopRecording(send: false, stopForReview: true);
  }

  /// Отправить запись (для locked режима)
  Future<void> sendRecording() async {
    // Если запись уже остановлена, отправляем остановленный файл
    if (_isStopped && _stoppedPath != null) {
      widget.onSend(_stoppedPath!, _stoppedDuration);
      _resetState();
      return;
    }
    await _stopRecording(send: true);
  }

  Future<void> _stopRecording({required bool send, bool stopForReview = false}) async {
    try {
      final stopStartTime = DateTime.now();
      print('🎤 [VoiceRecorder] Остановка записи - длительность до остановки: $_recordDuration сек, отправка: $send');
      print('🎤 [VoiceRecorder] Текущий путь к файлу: $_currentPath');
      print('🎤 [VoiceRecorder] Статус записи: _isRecording=$_isRecording, _isLocked=$_isLocked');
      
      // Сначала останавливаем таймеры, чтобы не было попыток получить амплитуду
      _timer?.cancel();
      _timer = null;
      _amplitudeTimer?.cancel();
      _amplitudeTimer = null;
      
      String? path;
      if (_isRecording) {
        try {
          // Проверяем, что запись действительно активна перед остановкой
          final isCurrentlyRecording = await _audioRecorder.isRecording();
          print('🎤 [VoiceRecorder] Проверка записи: isCurrentlyRecording=$isCurrentlyRecording');
          if (isCurrentlyRecording) {
            path = await _audioRecorder.stop();
            print('🎤 [VoiceRecorder] Запись остановлена, получен путь: $path');
            // Сохраняем путь, если он был получен
            if (path != null) {
              _currentPath = path;
              print('🎤 [VoiceRecorder] Путь сохранен в _currentPath: $_currentPath');
            }
          } else {
            print('🎤 [VoiceRecorder] Запись уже была остановлена ранее');
            print('🎤 [VoiceRecorder] Используем сохраненный путь: $_currentPath');
          }
        } catch (e) {
          print('🎤 [VoiceRecorder] Ошибка при остановке записи: $e');
          print('🎤 [VoiceRecorder] Пытаемся использовать сохраненный путь: $_currentPath');
        }
      } else {
        print('🎤 [VoiceRecorder] Запись не активна (_isRecording=false), используем сохраненный путь: $_currentPath');
      }

      // Используем путь из stop() или сохраненный путь
      final effectivePath = path ?? _currentPath;
      final duration = max(_recordDuration, 1);
      final stopEndTime = DateTime.now();
      final stopDuration = stopEndTime.difference(stopStartTime).inMilliseconds;

      setState(() {
        _isRecording = false;
      });

      if (effectivePath == null) {
        print('🎤 [VoiceRecorder] ❌ ОШИБКА: Путь к файлу отсутствует (path=$path, _currentPath=$_currentPath), отмена отправки');
        _resetState();
        widget.onCancel();
        return;
      }

      if (stopForReview) {
        // Остановка для переслушивания (не отправляем, не отменяем)
        final stopPath = effectivePath;
        final stopDuration = duration;
        print('🎤 [VoiceRecorder] ⏸️ Запись остановлена для переслушивания - путь: $stopPath, длительность: $stopDuration сек');
        // Сохраняем данные (UI уже обновлен в stopRecording)
        if (mounted) {
          setState(() {
            _stoppedPath = stopPath;
            _stoppedDuration = stopDuration;
          });
        }
        // Вызываем callback onStop если он есть
        if (widget.onStop != null) {
          widget.onStop!(stopPath, stopDuration);
        }
      } else if (send) {
        final sendPath = effectivePath;
        final sendDuration = duration;
        print('🎤 [VoiceRecorder] ✅ Файл готов к отправке - путь: $sendPath, длительность: $sendDuration сек, время остановки: ${stopDuration}ms');
        // НЕ сбрасываем состояние до отправки, чтобы путь сохранился
        // _resetState() будет вызван после успешной отправки или в onSend callback
        widget.onSend(sendPath, sendDuration);
        // Теперь можно сбросить состояние
        _resetState();
      } else {
        print('🎤 [VoiceRecorder] Запись отменена пользователем');
        _resetState();
        widget.onCancel();
      }
    } catch (e) {
      print('VoiceRecorderWidget: Error stopping recording: $e');
      // Убеждаемся, что таймеры остановлены даже при ошибке
      _timer?.cancel();
      _timer = null;
      _amplitudeTimer?.cancel();
      _amplitudeTimer = null;
      _resetState();
      widget.onCancel();
    }
  }

  void _resetState() {
    _isRecording = false;
    _isLocked = false;
    _isStopped = false;
    _recordDuration = 0;
    _currentPath = null;
    _stoppedPath = null;
    _stoppedDuration = 0;
    _amplitudes = List.generate(40, (_) => 0.0, growable: true);
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 12),
        // Таймер (показываем длительность остановленной записи если она остановлена)
        Text(
          _formatDuration(_isStopped ? _stoppedDuration : _recordDuration),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 12),
        // Визуализация волн
        Expanded(
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF1F1F1F),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: CustomPaint(
              painter: WaveformPainter(amplitudes: _amplitudes),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> amplitudes;

  WaveformPainter({required this.amplitudes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0095F6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final barWidth = size.width / amplitudes.length;

    for (int i = 0; i < amplitudes.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final barHeight = amplitudes[i] * size.height * 0.8;
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;

      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) => true;
}
