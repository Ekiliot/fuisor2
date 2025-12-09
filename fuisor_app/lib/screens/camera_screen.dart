import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'story_preview_screen.dart';
import '../widgets/app_notification.dart';

class CameraScreen extends StatefulWidget {
  final bool isGeoPost;
  final double? latitude;
  final double? longitude;

  const CameraScreen({
    super.key,
    this.isGeoPost = false,
    this.latitude,
    this.longitude,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;
  bool _isFrontCameraMode = false; // Режим фронтальной камеры: false = person (зум 1.5x), true = people (зум 1.0x - широкий)
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  double _recordingProgress = 0.0;
  Timer? _recordingTimer;
  Timer? _longPressTimer;
  bool _isLongPress = false;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;
  double _dragStartY = 0.0; // Начальная Y позиция при начале свайпа (глобальная)
  double _pointerStartY = 0.0; // Начальная Y позиция при касании
  double _pointerStartX = 0.0; // Начальная X позиция при касании
  bool _isVerticalDragging = false; // Флаг для отслеживания вертикального свайпа
  bool _isFingerDown = false; // Флаг для отслеживания касания пальца
  bool _isPointerOnButton = false; // Флаг, что палец начал касание на кнопке
  bool _isFlashOn = false; // Состояние вспышки (включена/выключена)
  bool _showGrid = false; // Показывать ли сетку
  bool _mirrorFrontCamera = true; // Отзеркаливание фронтальной камеры (по умолчанию включено)
  String _zoomSensitivity = 'normal'; // Чувствительность зума: 'weak', 'normal', 'strong'
  double _cameraOpacity = 1.0; // Прозрачность камеры (для затемнения)
  static const int _maxVideoDuration = 15; // 15 секунд максимум
  static const int _longPressDelay = 200; // 200ms для определения длинного нажатия

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    // Проверяем разрешения
    final cameraStatus = await Permission.camera.status;
    if (!cameraStatus.isGranted) {
      final result = await Permission.camera.request();
      if (!result.isGranted) {
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }
    }

    // Проверяем разрешение на микрофон
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      await Permission.microphone.request();
    }

    // Получаем доступные камеры
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Камера не найдена',
        );
        Navigator.of(context).pop();
      }
      return;
    }

    // Используем заднюю камеру (или первую доступную)
    _currentCameraIndex = _cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    if (_currentCameraIndex == -1) {
      _currentCameraIndex = 0;
    }
    final camera = _cameras[_currentCameraIndex];

    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.jpeg
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        // Инициализируем зум по умолчанию
        _minZoom = 1.0;
        _maxZoom = 1.0;
        _currentZoom = 1.0;
        _baseZoom = 1.0;
        
        // Если это фронтальная камера, инициализируем зум и устанавливаем правильный режим
        if (camera.lensDirection == CameraLensDirection.front) {
          await _initializeZoomIfNeeded();
          // Устанавливаем зум в зависимости от текущего режима
          // person mode (false) = 1.5x, people mode (true) = 1.0x
          double initialZoom = _isFrontCameraMode ? 1.0 : 1.5;
          try {
            double clampedZoom = initialZoom.clamp(_minZoom, _maxZoom);
            await _controller!.setZoomLevel(clampedZoom);
            _currentZoom = clampedZoom;
            _baseZoom = clampedZoom;
            print('Front camera initialized: mode=${_isFrontCameraMode ? "people" : "person"}, zoom=${clampedZoom}x');
          } catch (e) {
            print('Error setting initial zoom for front camera: $e');
          }
        }
        
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка инициализации камеры: $e',
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing || _isRecording) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Включаем вспышку только при съемке, если она включена в настройках
      FlashMode? originalFlashMode;
      if (_isFlashOn) {
        try {
          originalFlashMode = _controller!.value.flashMode;
          await _controller!.setFlashMode(FlashMode.always);
        } catch (e) {
          print('Error setting flash mode for photo: $e');
        }
      }

      final XFile photo = await _controller!.takePicture();
      
      // Выключаем вспышку после съемки
      if (_isFlashOn && originalFlashMode != null) {
        try {
          await _controller!.setFlashMode(FlashMode.off);
        } catch (e) {
          print('Error turning off flash after photo: $e');
        }
      }

      if (mounted) {
        // Останавливаем камеру перед переходом к превью
        if (_controller != null && _controller!.value.isInitialized) {
          try {
            await _controller!.stopVideoRecording(); // На случай, если запись еще идет
            await _controller!.pausePreview(); // Останавливаем превью камеры
          } catch (e) {
            print('Error stopping camera before navigation: $e');
          }
        }

        // Для всех случаев (включая гео-посты) показываем StoryPreviewScreen
        final imageBytes = await photo.readAsBytes();
        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => StoryPreviewScreen(
              selectedFile: photo,
              selectedImageBytes: imageBytes,
              isGeoPost: widget.isGeoPost,
              latitude: widget.latitude,
              longitude: widget.longitude,
            ),
          ),
        );

        // Возобновляем камеру после возврата из превью
        if (mounted && _controller != null && _controller!.value.isInitialized) {
          try {
            await _controller!.resumePreview();
          } catch (e) {
            print('Error resuming camera after navigation: $e');
          }
        }
        // Возвращаем результат обратно
        if (mounted && result != null) {
          Navigator.of(context).pop(result);
        }
      }
    } catch (e) {
      // Выключаем вспышку в случае ошибки
      if (_isFlashOn) {
        try {
          await _controller?.setFlashMode(FlashMode.off);
        } catch (flashError) {
          print('Error turning off flash after error: $flashError');
        }
      }
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка при съемке фото: $e',
        );
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    // Проверяем, находится ли точка касания в области кнопки
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    
    final Size screenSize = MediaQuery.of(context).size;
    final double buttonCenterX = screenSize.width / 2;
    final double buttonCenterY = screenSize.height - 40 - 40; // bottom: 40, button height: 80, center at 40
    final double buttonRadius = 50; // Радиус области кнопки (чуть больше самой кнопки)
    
    final double distanceFromButton = 
        ((event.position.dx - buttonCenterX) * (event.position.dx - buttonCenterX) +
         (event.position.dy - buttonCenterY) * (event.position.dy - buttonCenterY));
    
    if (distanceFromButton <= buttonRadius * buttonRadius) {
      // Касание в области кнопки
      _isPointerOnButton = true;
      _isFingerDown = true;
      _pointerStartY = event.position.dy;
      _pointerStartX = event.position.dx;
      
      // Запускаем таймер для определения длинного нажатия
      _longPressTimer = Timer(const Duration(milliseconds: _longPressDelay), () {
        if (!_isLongPress && !_isRecording && !_isProcessing && _isFingerDown && _isPointerOnButton) {
          _isLongPress = true;
          _startRecording();
        }
      });
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isFingerDown || !_isPointerOnButton) return;
    
    if (_isRecording) {
      // Вычисляем смещение от начальной позиции
      double deltaY = _pointerStartY - event.position.dy;
      double deltaX = (event.position.dx - _pointerStartX).abs();
      
      // Если вертикальное движение больше горизонтального, это зум
      if (deltaY.abs() > 10 && deltaY.abs() > deltaX) {
        if (!_isVerticalDragging) {
          // Начинаем зум
          _isVerticalDragging = true;
          _dragStartY = _pointerStartY;
          _baseZoom = _currentZoom;
          _initializeZoomIfNeeded();
          if (mounted) {
            setState(() {});
          }
        }
        
        // Вычисляем расстояние от начала жеста зума
        double totalDragDistance = _dragStartY - event.position.dy;
        _updateZoom(totalDragDistance);
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_isFingerDown) return;
    
    _isFingerDown = false;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    
    // Не обрабатываем отпускание, если идет вертикальный свайп (зум)
    if (_isVerticalDragging) {
      // Сбрасываем флаг после небольшой задержки
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_isFingerDown && _isRecording) {
          _stopRecording();
        }
      });
      _isVerticalDragging = false;
      _isPointerOnButton = false;
      return;
    }
    
    // Если записывали видео, останавливаем
    if (_isRecording) {
      _stopRecording();
    } else if (!_isLongPress && !_isProcessing && _isPointerOnButton) {
      // Если это было короткое нажатие (не длинное), делаем фото
      _takePhoto();
    }
    
    _isLongPress = false;
    _isPointerOnButton = false;
  }


  void _showCameraSettings() {
    // Плавно затемняем камеру
    setState(() {
      _cameraOpacity = 0.3;
    });
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _CameraSettingsSheet(
        showGrid: _showGrid,
        isFlashOn: _isFlashOn,
        mirrorFrontCamera: _mirrorFrontCamera,
        zoomSensitivity: _zoomSensitivity,
        onGridChanged: (value) {
          setState(() {
            _showGrid = value;
          });
        },
        onFlashChanged: (value) {
          setState(() {
            _isFlashOn = value;
          });
          // Не включаем вспышку сразу, только сохраняем настройку
          // Вспышка будет включаться только при съемке фото или записи видео
        },
        onMirrorFrontCameraChanged: (value) {
          setState(() {
            _mirrorFrontCamera = value;
          });
        },
        onZoomSensitivityChanged: (value) {
          setState(() {
            _zoomSensitivity = value;
          });
        },
        onClose: () {
          // Восстанавливаем прозрачность камеры
          setState(() {
            _cameraOpacity = 1.0;
          });
        },
      ),
    ).then((_) {
      // Восстанавливаем прозрачность камеры при закрытии
      setState(() {
        _cameraOpacity = 1.0;
      });
    });
  }

  // Переключение зума фронтальной камеры (искусственный wide mode через зум)
  // person mode: зум 1.5x (увеличение)
  // people mode: зум 1.0x (нормальный/широкий)
  // ВАЖНО: Этот метод должен вызываться ТОЛЬКО для фронтальной камеры
  Future<void> _switchFrontCameraZoom() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('Cannot switch zoom: camera not initialized');
      return;
    }
    
    // СТРОГАЯ ПРОВЕРКА: проверяем, что сейчас используется фронтальная камера
    if (_cameras.isEmpty || _currentCameraIndex >= _cameras.length) {
      print('Cannot switch zoom: no cameras available');
      return;
    }
    final currentCamera = _cameras[_currentCameraIndex];
    
    // СТРОГАЯ ПРОВЕРКА: зум-режимы (person/people) работают ТОЛЬКО для фронтальной камеры
    if (currentCamera.lensDirection != CameraLensDirection.front) {
      print('Cannot switch front camera zoom mode: not front camera (current: ${currentCamera.lensDirection})');
      // Если это не фронтальная камера, сбрасываем режим и зум на стандартный
      _isFrontCameraMode = false;
      _currentZoom = 1.0;
      _baseZoom = 1.0;
      // Также сбрасываем зум камеры на 1.0, если он был изменен
      if (_controller != null && _controller!.value.isInitialized && _currentZoom != 1.0) {
        try {
          await _controller!.setZoomLevel(1.0);
          _currentZoom = 1.0;
          _baseZoom = 1.0;
          if (mounted) setState(() {});
        } catch (e) {
          print('Error resetting zoom for back camera: $e');
        }
      }
      return;
    }

    try {
      // Инициализируем зум, если еще не инициализирован
      await _initializeZoomIfNeeded();
      
      // Переключаем режим
      _isFrontCameraMode = !_isFrontCameraMode;
      
      // Устанавливаем зум: false = person (1.5x), true = people (1.0x - широкий)
      double targetZoom;
      if (_isFrontCameraMode) {
        // Режим "people" (широкий) - зум 1.0x
        targetZoom = 1.0;
        print('Switching to people mode (wide): zoom=1.0x');
      } else {
        // Режим "person" (обычный) - зум 1.5x
        targetZoom = 1.5;
        print('Switching to person mode (normal): zoom=1.5x');
      }
      
      // Устанавливаем зум
      try {
        // Проверяем, что целевой зум находится в допустимом диапазоне
        double clampedZoom = targetZoom.clamp(_minZoom, _maxZoom);
        if (clampedZoom != targetZoom) {
          print('Target zoom $targetZoom clamped to $clampedZoom (range: $_minZoom - $_maxZoom)');
        }
        await _controller!.setZoomLevel(clampedZoom);
        _currentZoom = clampedZoom;
        _baseZoom = clampedZoom;
        print('Zoom set successfully: ${_currentZoom}x');
      } catch (zoomError) {
        print('Failed to set zoom $targetZoom: $zoomError');
        // Откатываем изменение режима при ошибке
        _isFrontCameraMode = !_isFrontCameraMode;
        if (mounted) {
          AppNotification.showError(
            context,
            'Ошибка установки зума: $zoomError',
          );
        }
        return;
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // Если произошла ошибка, возвращаем состояние
      print('Error switching front camera zoom mode: $e');
      _isFrontCameraMode = !_isFrontCameraMode;
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка переключения режима: $e',
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length <= 1 || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    try {
      setState(() {
        _isInitialized = false;
      });

      // Останавливаем запись, если она идет
      if (_isRecording) {
        await _stopRecording();
      }

      // Освобождаем текущий контроллер
      await _controller!.dispose();

      // Переключаемся на другую камеру
      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
      final camera = _cameras[_currentCameraIndex];
      
      // Сбрасываем режим фронтальной камеры при переключении
      if (camera.lensDirection == CameraLensDirection.back) {
        // Для задней камеры сбрасываем режим и зум на стандартный (1.0)
        _isFrontCameraMode = false;
        _currentZoom = 1.0;
        _baseZoom = 1.0;
        print('Switched to back camera: reset zoom to 1.0');
      } else if (camera.lensDirection == CameraLensDirection.front) {
        // При переключении на фронтальную камеру устанавливаем person режим (зум 1.5x) по умолчанию
        _isFrontCameraMode = false;
        _currentZoom = 1.5;
        _baseZoom = 1.5;
        print('Switched to front camera: reset zoom to 1.5x, mode=person');
      }

      // Создаем новый контроллер
      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.jpeg
            : ImageFormatGroup.bgra8888,
      );

      // Инициализируем новую камеру
      await _controller!.initialize();

      // Сбрасываем зум
      _minZoom = 1.0;
      _maxZoom = 1.0;
      _currentZoom = 1.0;
      _baseZoom = 1.0;

      // Если это фронтальная камера, инициализируем зум и устанавливаем правильный режим
      if (camera.lensDirection == CameraLensDirection.front) {
        await _initializeZoomIfNeeded();
        // Устанавливаем зум в зависимости от текущего режима
        // person mode (false) = 1.5x, people mode (true) = 1.0x
        double initialZoom = _isFrontCameraMode ? 1.0 : 1.5;
        try {
          double clampedZoom = initialZoom.clamp(_minZoom, _maxZoom);
          await _controller!.setZoomLevel(clampedZoom);
          _currentZoom = clampedZoom;
          _baseZoom = clampedZoom;
          print('Front camera initialized: mode=${_isFrontCameraMode ? "people" : "person"}, zoom=${clampedZoom}x');
        } catch (e) {
          print('Error setting initial zoom for front camera: $e');
        }
      } else {
        // Для задней камеры сразу устанавливаем зум на 1.0
        try {
          await _controller!.setZoomLevel(1.0);
        } catch (e) {
          print('Error setting zoom to 1.0 for back camera: $e');
        }
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка переключения камеры: $e',
        );
        setState(() {
          _isInitialized = false;
        });
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    try {
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
      // Не включаем вспышку сразу, только сохраняем настройку
      // Вспышка будет включаться только при съемке фото или записи видео
    } catch (e) {
      // Если произошла ошибка, возвращаем состояние
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    }
  }


  Future<void> _initializeZoomIfNeeded() async {
    // Инициализируем зум только если еще не инициализирован
    if (_minZoom == 1.0 && _maxZoom == 1.0 && _controller != null && _controller!.value.isInitialized) {
      try {
        // Небольшая задержка для стабильности
        await Future.delayed(const Duration(milliseconds: 200));
        
        if (_controller != null && _controller!.value.isInitialized) {
          _minZoom = await _controller!.getMinZoomLevel();
          _maxZoom = await _controller!.getMaxZoomLevel();
          
          // Не меняем _currentZoom, если он уже установлен (например, для режима person)
          // Только если он еще не был установлен явно
          if (_currentZoom == 1.0 && _baseZoom == 1.0) {
            // По умолчанию используем обычный зум (1.0), а не минимальный
            _currentZoom = 1.0;
            _baseZoom = 1.0;
          }
          
          print('Zoom initialized: min=$_minZoom, max=$_maxZoom, current=$_currentZoom');
          
          if (mounted) {
            setState(() {});
          }
        }
      } catch (e) {
        // Если зум не поддерживается, оставляем значения по умолчанию
        print('Error initializing zoom: $e');
      }
    }
  }

  void _updateZoom(double totalDragDistance) {
    // Вычисляем изменение зума на основе общего расстояния
    // Свайп вверх (отрицательное расстояние) = увеличение зума
    // Свайп вниз (положительное расстояние) = уменьшение зума
    // Чувствительность зума в зависимости от настройки
    double zoomSensitivity;
    switch (_zoomSensitivity) {
      case 'weak':
        zoomSensitivity = 0.004; // Слабая
        break;
      case 'strong':
        zoomSensitivity = 0.012; // Сильная
        break;
      case 'normal':
      default:
        zoomSensitivity = 0.008; // Нормальная
        break;
    }
    double zoomDelta = totalDragDistance * zoomSensitivity;
    
    double newZoom = _baseZoom + zoomDelta;
    
    // Ограничиваем зум минимальным и максимальным значениями
    newZoom = newZoom.clamp(_minZoom, _maxZoom);
    
    // Обновляем зум только если изменение значительное (для плавности)
    if ((newZoom - _currentZoom).abs() > 0.001) {
      _currentZoom = newZoom;
      if (mounted) {
        setState(() {
          // Обновляем состояние для индикатора зума
        });
      }
      try {
        _controller!.setZoomLevel(_currentZoom);
      } catch (e) {
        // Игнорируем ошибки зума, если устройство не поддерживает
      }
    }
  }


  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRecording) {
      return;
    }

    if (!_controller!.value.isRecordingVideo) {
      try {
        // Включаем вспышку только при записи, если она включена в настройках
        if (_isFlashOn) {
          try {
            await _controller!.setFlashMode(FlashMode.torch);
          } catch (e) {
            print('Error setting flash mode for video: $e');
          }
        }

        await _controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
          _recordingProgress = 0.0;
        });

        // Запускаем таймер для прогресс-бара
        _recordingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
          if (mounted) {
            setState(() {
              _recordingProgress += 0.05 / _maxVideoDuration; // 50ms / 15000ms
              if (_recordingProgress >= 1.0) {
                _recordingProgress = 1.0;
                _stopRecording();
              }
            });
          }
        });

        // Автоматически останавливаем через 15 секунд
        Future.delayed(const Duration(seconds: _maxVideoDuration), () {
          if (_isRecording) {
            _stopRecording();
          }
        });
      } catch (e) {
        // Выключаем вспышку в случае ошибки
        if (_isFlashOn) {
          try {
            await _controller?.setFlashMode(FlashMode.off);
          } catch (flashError) {
            print('Error turning off flash after error: $flashError');
          }
        }
        if (mounted) {
          AppNotification.showError(
            context,
            'Ошибка при начале записи: $e',
          );
        }
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      final XFile videoFile = await _controller!.stopVideoRecording();
      
      // Выключаем вспышку после остановки записи
      if (_isFlashOn) {
        try {
          await _controller!.setFlashMode(FlashMode.off);
        } catch (e) {
          print('Error turning off flash after recording: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingProgress = 0.0;
          _isProcessing = true;
        });
      }

      // Определяем, нужно ли отзеркаливать видео
      final shouldMirror = _cameras.isNotEmpty && 
          _currentCameraIndex < _cameras.length &&
          _cameras[_currentCameraIndex].lensDirection == CameraLensDirection.front &&
          _mirrorFrontCamera;

      String finalVideoPath = videoFile.path;

      // Обрабатываем видео СРАЗУ после остановки записи, если нужно
      if (shouldMirror) {
        try {
          final tempDir = await getTemporaryDirectory();
          final outputPath = '${tempDir.path}/mirrored_${DateTime.now().millisecondsSinceEpoch}.mp4';
          
          // Применяем отзеркаливание через FFmpeg
          final command = '-i "${videoFile.path}" -vf "hflip" -c:a copy "$outputPath"';
          final session = await FFmpegKit.execute(command);
          final returnCode = await session.getReturnCode();
          
          if (ReturnCode.isSuccess(returnCode)) {
            finalVideoPath = outputPath;
          } else {
            // Если обработка не удалась, используем оригинальное видео
            print('Ошибка обработки видео (код: $returnCode), используем оригинал');
          }
        } catch (e) {
          print('Ошибка при обработке видео: $e');
          // Используем оригинальное видео
        }
      }

      // Только после обработки показываем превью
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        // Останавливаем камеру перед переходом к превью
        if (_controller != null && _controller!.value.isInitialized) {
          try {
            await _controller!.pausePreview(); // Останавливаем превью камеры
          } catch (e) {
            print('Error stopping camera before video navigation: $e');
          }
        }

        // Для всех случаев (включая гео-посты) показываем StoryPreviewScreen
        final videoFile = XFile(finalVideoPath);
        // Создаем контроллер для видео
        final videoController = VideoPlayerController.file(File(finalVideoPath));
        await videoController.initialize();

        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => StoryPreviewScreen(
              selectedFile: videoFile,
              videoController: videoController,
              isGeoPost: widget.isGeoPost,
              latitude: widget.latitude,
              longitude: widget.longitude,
            ),
          ),
        );

        // Возобновляем камеру после возврата из превью видео
        if (mounted && _controller != null && _controller!.value.isInitialized) {
          try {
            await _controller!.resumePreview();
          } catch (e) {
            print('Error resuming camera after video navigation: $e');
          }
        }

        // Если пользователь вернулся, возвращаем результат
        if (mounted && result != null) {
          Navigator.of(context).pop(result);
        }
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка при остановке записи: $e',
        );
        setState(() {
          _isRecording = false;
          _recordingProgress = 0.0;
          _isProcessing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    
    // Правильно освобождаем камеру
    if (_controller != null) {
      if (_controller!.value.isInitialized) {
        // Останавливаем запись, если она идет
        if (_isRecording) {
          _controller!.stopVideoRecording().then((_) {
            // Запись остановлена
          }).catchError((e) {
            print('Error stopping video recording in dispose: $e');
          });
        }
      }
      // Освобождаем контроллер
      _controller!.dispose().catchError((e) {
        print('Error disposing camera controller: $e');
      });
      _controller = null;
    }
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          // Останавливаем запись, если она идет
          if (_isRecording) {
            try {
              await _controller?.stopVideoRecording();
            } catch (e) {
              print('Error stopping recording on pop: $e');
            }
          }
          // Освобождаем камеру перед выходом
          if (_controller != null && _controller!.value.isInitialized) {
            try {
              await _controller!.dispose();
            } catch (e) {
              print('Error disposing camera on pop: $e');
            }
            _controller = null;
          }
          // Используем fade анимацию при выходе
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
        child: Listener(
          onPointerDown: (PointerDownEvent event) {
            _handlePointerDown(event);
          },
          onPointerMove: (PointerMoveEvent event) {
            _handlePointerMove(event);
          },
          onPointerUp: (PointerUpEvent event) {
            _handlePointerUp(event);
          },
          onPointerCancel: (PointerCancelEvent event) {
            // Обрабатываем отмену как отпускание
            if (_isFingerDown) {
              _isFingerDown = false;
              _longPressTimer?.cancel();
              _longPressTimer = null;
              _isPointerOnButton = false;
              _isVerticalDragging = false;
            }
          },
          child: Stack(
            children: [
              // Камера с закругленными краями в портретном режиме 9:16
              if (_isInitialized && _controller != null)
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Вычисляем размер для соотношения 9:16 (портретный режим)
                      final screenWidth = constraints.maxWidth;
                      final screenHeight = constraints.maxHeight;
                      
                      // Соотношение 9:16 означает ширина:высота = 9:16
                      // Вычисляем максимальную высоту и соответствующую ширину
                      double cameraHeight = screenHeight;
                      double cameraWidth = cameraHeight * 9 / 16;
                      
                      // Если вычисленная ширина больше ширины экрана, уменьшаем по ширине
                      if (cameraWidth > screenWidth) {
                        cameraWidth = screenWidth;
                        cameraHeight = cameraWidth * 16 / 9;
                      }
                      
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedOpacity(
                          opacity: _cameraOpacity,
                          duration: const Duration(milliseconds: 300),
                          child: SizedBox(
                            width: cameraWidth,
                            height: cameraHeight,
                            child: GestureDetector(
                              onDoubleTap: () {
                                // Двойной тап для переключения между фронтальной и задней камерой
                                if (_cameras.length > 1) {
                                  _switchCamera();
                                }
                              },
                              child: Stack(
                                children: [
                                  // Отзеркаливание для фронтальной камеры
                                  Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..scale(
                                        (_cameras.isNotEmpty && 
                                         _currentCameraIndex < _cameras.length &&
                                         _cameras[_currentCameraIndex].lensDirection == CameraLensDirection.front &&
                                         !_mirrorFrontCamera) ? -1.0 : 1.0,
                                        1.0,
                                      ),
                                    child: CameraPreview(_controller!),
                                  ),
                                  // Сетка (если включена)
                                  if (_showGrid)
                                    CustomPaint(
                                      painter: GridPainter(),
                                      size: Size(cameraWidth, cameraHeight),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  ),
                )
            else
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),

            // Кнопка настроек в левом верхнем углу
            Positioned(
              top: 16,
              left: 16,
              child: GestureDetector(
                onTap: () {
                  _showCameraSettings();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    EvaIcons.settingsOutline,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),

            // Кнопка вспышки в правом верхнем углу
            Positioned(
              top: 16,
              right: 16,
              child: GestureDetector(
                onTap: () {
                  _toggleFlash();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    _isFlashOn ? EvaIcons.flash : EvaIcons.flashOutline,
                    color: _isFlashOn ? Colors.yellow : Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),

            // Индикатор зума вверху экрана (только во время записи)
            if (_isRecording)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _isVerticalDragging ? 1.0 : 0.7,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Текст с текущим зумом
                          Text(
                            '${_currentZoom.toStringAsFixed(1)}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Полоса прогресса зума
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: _minZoom,
                              end: _currentZoom,
                            ),
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOut,
                            builder: (context, value, child) {
                              // Вычисляем процент зума от минимального до максимального
                              double zoomRange = _maxZoom - _minZoom;
                              double zoomProgress = zoomRange > 0
                                  ? (value - _minZoom) / zoomRange
                                  : 0.0;
                              
                              return Container(
                                width: 60,
                                height: 3,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(1.5),
                                  color: Colors.white.withOpacity(0.2),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: zoomProgress.clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(1.5),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFF3B30),
                                          Color(0xFFFF6B35),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Вкладки для изменения зума фронтальной камеры (только если фронтальная камера активна)
            if (_cameras.isNotEmpty && 
                _currentCameraIndex < _cameras.length &&
                _cameras[_currentCameraIndex].lensDirection == CameraLensDirection.front)
              Positioned(
                bottom: 130,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Обычный зум (person)
                        GestureDetector(
                          onTap: () {
                            if (_isFrontCameraMode) {
                              _switchFrontCameraZoom();
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: !_isFrontCameraMode
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  EvaIcons.personOutline,
                                  color: !_isFrontCameraMode
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.6),
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Минимальный зум (people - широкий режим)
                        GestureDetector(
                          onTap: () {
                            if (!_isFrontCameraMode) {
                              _switchFrontCameraZoom();
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: _isFrontCameraMode
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  EvaIcons.peopleOutline,
                                  color: _isFrontCameraMode
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.6),
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Кнопка съемки внизу
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Stack(
                children: [
                  // Кнопка записи (строго по центру)
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                      // Прогресс-бар вокруг кнопки (только при записи) - больше кнопки
                      if (_isRecording)
                        Container(
                          width: 100,
                          height: 100,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: _recordingProgress),
                            duration: const Duration(milliseconds: 50),
                            builder: (context, value, child) {
                              return CircularProgressIndicator(
                                value: value,
                                strokeWidth: 3.5,
                                strokeCap: StrokeCap.round,
                                backgroundColor: Colors.white.withOpacity(0.2),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFFFF3B30),
                                ),
                              );
                            },
                          ),
                        ),
                      // Кнопка (не уменьшается при записи)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Внешний белый круг с градиентом
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: _isRecording
                                      ? [
                                          Colors.white.withOpacity(0.9),
                                          Colors.white.withOpacity(0.7),
                                        ]
                                      : [
                                          Colors.white,
                                          Colors.white.withOpacity(0.95),
                                        ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.8),
                                  width: 4,
                                ),
                              ),
                            ),
                            // Внутренний круг с анимацией
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isRecording
                                    ? const Color(0xFFFF3B30)
                                    : Colors.white,
                                boxShadow: _isRecording
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFFF3B30).withOpacity(0.5),
                                          blurRadius: 12,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 4,
                                          spreadRadius: 1,
                                        ),
                                      ],
                              ),
                              child: _isRecording
                                  ? Center(
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          color: Colors.white,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                  // Кнопка переключения камеры (центрирована между левым краем и центром)
                  if (_cameras.length > 1)
                    Positioned(
                      left: MediaQuery.of(context).size.width / 4 - 22, // Середина между левым краем и центром, минус половина ширины кнопки
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _switchCamera,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              EvaIcons.flip2Outline,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
      ),
    );
  }

}

// Класс для отрисовки сетки
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1.0;

    // Вертикальные линии (делим на 3 части)
    final verticalSpacing = size.width / 3;
    for (int i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(verticalSpacing * i, 0),
        Offset(verticalSpacing * i, size.height),
        paint,
      );
    }

    // Горизонтальные линии (делим на 3 части)
    final horizontalSpacing = size.height / 3;
    for (int i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(0, horizontalSpacing * i),
        Offset(size.width, horizontalSpacing * i),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Модальное окно настроек камеры
class _CameraSettingsSheet extends StatefulWidget {
  final bool showGrid;
  final bool isFlashOn;
  final bool mirrorFrontCamera;
  final String zoomSensitivity;
  final ValueChanged<bool> onGridChanged;
  final ValueChanged<bool> onFlashChanged;
  final ValueChanged<bool> onMirrorFrontCameraChanged;
  final ValueChanged<String> onZoomSensitivityChanged;
  final VoidCallback onClose;

  const _CameraSettingsSheet({
    required this.showGrid,
    required this.isFlashOn,
    required this.mirrorFrontCamera,
    required this.zoomSensitivity,
    required this.onGridChanged,
    required this.onFlashChanged,
    required this.onMirrorFrontCameraChanged,
    required this.onZoomSensitivityChanged,
    required this.onClose,
  });

  @override
  State<_CameraSettingsSheet> createState() => _CameraSettingsSheetState();
}

class _CameraSettingsSheetState extends State<_CameraSettingsSheet> {
  late bool _localShowGrid;
  late bool _localIsFlashOn;
  late bool _localMirrorFrontCamera;
  late String _localZoomSensitivity;

  @override
  void initState() {
    super.initState();
    _localShowGrid = widget.showGrid;
    _localIsFlashOn = widget.isFlashOn;
    _localMirrorFrontCamera = widget.mirrorFrontCamera;
    _localZoomSensitivity = widget.zoomSensitivity;
  }

  @override
  void didUpdateWidget(_CameraSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showGrid != widget.showGrid) {
      _localShowGrid = widget.showGrid;
    }
    if (oldWidget.isFlashOn != widget.isFlashOn) {
      _localIsFlashOn = widget.isFlashOn;
    }
    if (oldWidget.mirrorFrontCamera != widget.mirrorFrontCamera) {
      _localMirrorFrontCamera = widget.mirrorFrontCamera;
    }
    if (oldWidget.zoomSensitivity != widget.zoomSensitivity) {
      _localZoomSensitivity = widget.zoomSensitivity;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Camera Settings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Grid
            _buildSettingItem(
              icon: EvaIcons.gridOutline,
              title: 'Grid',
              value: _localShowGrid,
              onChanged: (value) {
                setState(() {
                  _localShowGrid = value;
                });
                widget.onGridChanged(value);
              },
            ),
            
            const Divider(
              color: Color(0xFF404040),
              height: 1,
              thickness: 0.5,
            ),
            
            // Flash
            _buildSettingItem(
              icon: EvaIcons.flashOutline,
              title: 'Flash',
              value: _localIsFlashOn,
              onChanged: (value) {
                setState(() {
                  _localIsFlashOn = value;
                });
                widget.onFlashChanged(value);
              },
            ),
            
            const Divider(
              color: Color(0xFF404040),
              height: 1,
              thickness: 0.5,
            ),
            
            // Mirror Front Camera
            _buildSettingItem(
              icon: EvaIcons.flip2Outline,
              title: 'Mirror Front Camera',
              value: _localMirrorFrontCamera,
              onChanged: (value) {
                setState(() {
                  _localMirrorFrontCamera = value;
                });
                widget.onMirrorFrontCameraChanged(value);
              },
            ),
            
            const Divider(
              color: Color(0xFF404040),
              height: 1,
              thickness: 0.5,
            ),
            
            // Zoom Sensitivity
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(
                    EvaIcons.settingsOutline,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Zoom Sensitivity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Zoom Sensitivity Options
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildZoomSensitivityOption('weak', 'Low', _localZoomSensitivity, (value) {
                    setState(() {
                      _localZoomSensitivity = value;
                    });
                    widget.onZoomSensitivityChanged(value);
                  }),
                  const SizedBox(width: 12),
                  _buildZoomSensitivityOption('normal', 'Normal', _localZoomSensitivity, (value) {
                    setState(() {
                      _localZoomSensitivity = value;
                    });
                    widget.onZoomSensitivityChanged(value);
                  }),
                  const SizedBox(width: 12),
                  _buildZoomSensitivityOption('strong', 'High', _localZoomSensitivity, (value) {
                    setState(() {
                      _localZoomSensitivity = value;
                    });
                    widget.onZoomSensitivityChanged(value);
                  }),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF262626),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: value 
                      ? const Color(0xFF0095F6).withOpacity(0.2)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: value 
                      ? const Color(0xFF0095F6)
                      : Colors.white.withOpacity(0.7),
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: 52,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: value 
                      ? const Color(0xFF0095F6)
                      : Colors.white.withOpacity(0.2),
                ),
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      left: value ? 22 : 2,
                      top: 2,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoomSensitivityOption(
    String value,
    String label,
    String currentValue,
    ValueChanged<String> onChanged,
  ) {
    final isSelected = currentValue == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF0095F6).withOpacity(0.2)
                : const Color(0xFF262626),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF0095F6)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? const Color(0xFF0095F6) : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

