import 'dart:math';
import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../widgets/app_notification.dart';

class VoiceMessagePlayer extends StatefulWidget {
  final String? audioUrl; // Публичный URL (deprecated, используйте mediaPath)
  final String? mediaPath; // Путь к файлу в storage (userId/chatId/filename.m4a)
  final String chatId; // ID чата для получения signed URL
  final int duration; // in seconds
  final bool isOwnMessage;

  const VoiceMessagePlayer({
    super.key,
    this.audioUrl, // Оставляем для обратной совместимости
    this.mediaPath, // Новый параметр - путь к файлу
    required this.chatId,
    required this.duration,
    required this.isOwnMessage,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ApiService _apiService = ApiService();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoading = false;
  String? _signedUrl; // Кэшированный signed URL
  bool _isGettingSignedUrl = false;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    print('VoiceMessagePlayer: initState - audioUrl: ${widget.audioUrl}, mediaPath: ${widget.mediaPath}, chatId: ${widget.chatId}, duration: ${widget.duration}');
    _duration = Duration(seconds: widget.duration);
    
    // Анимация для волн (плавнее)
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
        // Запускаем/останавливаем анимацию волн
        if (_isPlaying) {
          _waveController.repeat();
        } else {
          _waveController.stop();
        }
        
        // Обновляем UI для плавного перехода
        if (mounted) {
          setState(() {});
        }
      }
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
        _waveController.stop();
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<String?> _getSignedUrl() async {
    // Если signed URL уже получен, возвращаем его
    if (_signedUrl != null) {
      return _signedUrl;
    }

    // Если нет mediaPath, используем старый способ (для обратной совместимости)
    if (widget.mediaPath == null) {
      print('VoiceMessagePlayer: Используется старый audioUrl (без signed URL)');
      return widget.audioUrl;
    }

    // Получаем signed URL
    if (_isGettingSignedUrl) {
      print('VoiceMessagePlayer: Signed URL уже запрашивается, ожидание...');
      // Ждем немного и проверяем снова
      await Future.delayed(const Duration(milliseconds: 100));
      return _signedUrl;
    }

    setState(() {
      _isGettingSignedUrl = true;
    });

    try {
      // Загружаем токен из SharedPreferences и устанавливаем его в ApiService
      print('VoiceMessagePlayer: Загрузка токена авторизации...');
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        throw Exception('No access token found. Please login again.');
      }
      
      // Устанавливаем токен в ApiService
      _apiService.setAccessToken(accessToken);
      print('VoiceMessagePlayer: Токен установлен в ApiService');
      
      print('VoiceMessagePlayer: Получение signed URL для ${widget.mediaPath}');
      final signedUrl = await _apiService.getMediaSignedUrl(
        chatId: widget.chatId,
        mediaPath: widget.mediaPath!,
      );
      
      if (mounted) {
        setState(() {
          _signedUrl = signedUrl;
          _isGettingSignedUrl = false;
        });
        print('VoiceMessagePlayer: ✅ Signed URL получен');
        return signedUrl;
      }
    } catch (e) {
      print('VoiceMessagePlayer: ❌ Ошибка получения signed URL: $e');
      if (mounted) {
        setState(() {
          _isGettingSignedUrl = false;
        });
        AppNotification.showError(
          context,
          'Failed to load audio: $e',
        );
      }
    }

    return null;
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      setState(() {
        _isLoading = true;
      });
      try {
        // Получаем signed URL перед воспроизведением
        final urlToPlay = await _getSignedUrl();
        
        if (urlToPlay == null) {
          throw Exception('Failed to get audio URL');
        }

        print('VoiceMessagePlayer: Воспроизведение аудио: $urlToPlay');
        await _audioPlayer.play(UrlSource(urlToPlay));
      } catch (e) {
        print('VoiceMessagePlayer: ❌ Ошибка воспроизведения аудио: $e');
        if (mounted) {
          AppNotification.showError(
            context,
            'Failed to play audio: $e',
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  // Генерирует амплитуды волн на основе прогресса воспроизведения (реалистичная анимация под звук)
  List<double> _generateWaveformAmplitudes(double progress, bool isPlaying) {
    final amplitudes = <double>[];
    final numBars = 30; // Количество полосок в волне
    final time = _waveController.value * 2 * pi; // Время для анимации (0-2π)
    
    for (int i = 0; i < numBars; i++) {
      double amplitude = 0.3;
      final position = i / numBars;
      
      if (isPlaying) {
        // При воспроизведении - создаем реалистичную волну, синхронизированную с позицией воспроизведения
        // Волны должны реагировать на "текущую позицию" как на реальный звук
        
        // Базовая позиция в аудио (где мы находимся)
        final audioPos = progress * numBars; // Позиция в барах
        final distanceFromAudioPos = (i - audioPos).abs(); // Расстояние от текущей позиции
        
        // Основная волна - более динамичная вблизи текущей позиции
        final wavePos = (position * 3 * pi) + (time * 0.5);
        final baseWave = sin(wavePos);
        
        // Усиление волны вблизи текущей позиции воспроизведения (имитация реального звука)
        final proximityEffect = distanceFromAudioPos < 5 
            ? (1.0 - (distanceFromAudioPos / 5) * 0.6) // Усиление до 60% вблизи текущей позиции
            : 0.7;
        
        // Дополнительные гармоники для реалистичности
        final wave1 = sin(wavePos * 1.5 + time * 0.3) * 0.3 * proximityEffect;
        final wave2 = cos(wavePos * 2.0 - time * 0.4) * 0.2 * proximityEffect;
        final wave3 = sin(wavePos * 0.7 + time * 0.6) * 0.15 * proximityEffect;
        
        // Комбинируем волны с учетом близости к текущей позиции
        final combined = (baseWave * proximityEffect + wave1 + wave2 + wave3 + 2) / 4;
        
        // Нормализация с учетом прогресса
        if (position <= progress) {
          // Пройденная часть - активная анимация
          amplitude = combined.clamp(0.35, 0.95);
        } else {
          // Непройденная часть - затухающая анимация
          final fade = (1.0 - ((position - progress) / (1.0 - progress)).clamp(0.0, 1.0));
          amplitude = (combined * fade).clamp(0.25, 0.5);
        }
        
        // Плавная пульсация для живости
        final pulse = sin(time + position * pi * 2) * 0.1;
        amplitude += pulse;
        amplitude = amplitude.clamp(0.25, 1.0);
        
      } else {
        // Когда не играет - статическая волна на основе прогресса
        if (position <= progress) {
          // Пройденная часть - показываем плавную волну
          final wavePos = position * 2.5 * pi;
          final wave = sin(wavePos) * 0.25 + 0.55;
          amplitude = wave.clamp(0.35, 0.75);
        } else {
          // Непройденная часть - плавный переход к минимальной амплитуде
          final distanceFromProgress = (position - progress) / (1 - progress);
          // Плавное затухание
          amplitude = 0.25 + (0.1 * (1 - distanceFromProgress));
          amplitude = amplitude.clamp(0.25, 0.35);
        }
      }
      
      amplitudes.add(amplitude);
    }
    
    return amplitudes;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isOwnMessage
            ? const Color(0xFF0095F6)
            : const Color(0xFF262626),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _isLoading ? null : _togglePlayPause,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      _isPlaying ? EvaIcons.pauseCircle : EvaIcons.playCircle,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Waveform visualization
          Expanded(
            child: SizedBox(
              height: 32,
              child: AnimatedBuilder(
                animation: _waveController,
                builder: (context, child) {
                  final amplitudes = _generateWaveformAmplitudes(progress, _isPlaying);
                  return CustomPaint(
                    painter: VoiceWaveformPainter(
                      amplitudes: amplitudes,
                      progress: progress,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Duration
          Text(
            _formatDuration(_duration),
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class VoiceWaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;
  final Color color;

  VoiceWaveformPainter({
    required this.amplitudes,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barSpacing = size.width / (amplitudes.length + 1);
    final maxBarHeight = size.height * 0.8;

    for (int i = 0; i < amplitudes.length; i++) {
      final x = (i + 1) * barSpacing;
      final centerY = size.height / 2;
      
      // Высота полоски на основе амплитуды
      final barHeight = amplitudes[i] * maxBarHeight;
      
      // Прогресс - плавная белая полоса с широкой зоной перехода
      final position = i / amplitudes.length;
      double opacity;
      
      final distanceFromProgress = position - progress;
      final transitionZone = 0.15; // Широкая зона плавного перехода (15% от длины)
      
      if (distanceFromProgress <= 0) {
        // Пройденная часть - полная яркость
        opacity = 1.0;
      } else if (distanceFromProgress <= transitionZone) {
        // Плавный переход - используем более плавную функцию (ease-out)
        final t = distanceFromProgress / transitionZone;
        // Используем квадратичную интерполяцию для более плавного перехода
        final easedT = 1.0 - (1.0 - t) * (1.0 - t); // ease-out curve
        opacity = 1.0 - (easedT * 0.6); // Плавный переход от 1.0 к 0.4
      } else {
        // Непройденная часть - затемнена
        opacity = 0.4;
      }
      
      final adjustedPaint = Paint()
        ..color = color.withOpacity(opacity)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      final y1 = centerY - barHeight / 2;
      final y2 = centerY + barHeight / 2;

      canvas.drawLine(Offset(x, y1), Offset(x, y2), adjustedPaint);
    }
  }

  @override
  bool shouldRepaint(VoiceWaveformPainter oldDelegate) {
    return oldDelegate.amplitudes != amplitudes ||
        oldDelegate.progress != progress;
  }
}

