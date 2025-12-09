import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomImageCropper extends StatefulWidget {
  final Uint8List imageBytes;

  const CustomImageCropper({
    super.key,
    required this.imageBytes,
  });

  @override
  State<CustomImageCropper> createState() => _CustomImageCropperState();
}

class _CustomImageCropperState extends State<CustomImageCropper> {
  final TransformationController _transformationController = TransformationController();
  ui.Image? _image;
  bool _isLoading = true;
  double _rotation = 0.0; // Угол поворота в градусах
  bool _flipHorizontal = false; // Отразить по горизонтали
  bool _flipVertical = false; // Отразить по вертикали
  double _minScale = 1.0;
  double _maxScale = 4.0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _image = frame.image;
      _isLoading = false;
    });
    
    // Устанавливаем начальный масштаб после загрузки изображения
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _image != null) {
        _initializeTransform();
      }
    });
  }
  
  void _initializeTransform() {
    final size = MediaQuery.of(context).size;
    final cropSize = size.width - 32; // Оставляем отступы
    
    if (_image == null) return;
    
    // Вычисляем соотношение сторон
    final imageAspectRatio = _image!.width / _image!.height;
    
    // Вычисляем размеры контента, чтобы он покрывал область кадрирования по одной стороне
    // и был больше или равен по другой
    double childWidth, childHeight;
    if (imageAspectRatio > 1) {
      // Горизонтальное изображение: высота = cropSize, ширина > cropSize
      childHeight = cropSize;
      childWidth = cropSize * imageAspectRatio;
    } else {
      // Вертикальное изображение: ширина = cropSize, высота > cropSize
      childWidth = cropSize;
      childHeight = cropSize / imageAspectRatio;
    }
    
    // Минимальный масштаб всегда 1.0, так как мы подогнали размеры child под cropSize
    _minScale = 1.0;
    
    // Устанавливаем начальный масштаб
    final initialScale = 1.0;
    
    // Центрируем изображение относительно cropSize
    // translation должен быть отрицательным или 0, чтобы центрировать контент, который больше viewport
    final offsetX = (cropSize - childWidth) / 2;
    final offsetY = (cropSize - childHeight) / 2;
    
    _transformationController.value = Matrix4.identity()
      ..translate(offsetX, offsetY)
      ..scale(initialScale);
    
    setState(() {});
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<Uint8List> _cropImage() async {
    if (_image == null) return widget.imageBytes;

    final size = MediaQuery.of(context).size;
    final cropSize = size.width - 32;
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();

    // Вычисляем размеры child
    final imageAspectRatio = _image!.width / _image!.height;
    double childWidth, childHeight;
    if (imageAspectRatio > 1) {
      childHeight = cropSize;
      childWidth = cropSize * imageAspectRatio;
    } else {
      childWidth = cropSize;
      childHeight = cropSize / imageAspectRatio;
    }

    // translation - это смещение левого верхнего угла child относительно (0,0) viewport
    // Координата (0,0) viewport соответствует точке (-translation.x, -translation.y) на child (масштабированном)
    
    final relativeCropX = -translation.x / scale;
    final relativeCropY = -translation.y / scale;
    final relativeCropSize = cropSize / scale;

    // Ограничиваем координаты, чтобы не вылезти за пределы child
    final safeCropX = relativeCropX.clamp(0.0, childWidth - relativeCropSize.clamp(0.0, childWidth));
    final safeCropY = relativeCropY.clamp(0.0, childHeight - relativeCropSize.clamp(0.0, childHeight));
    final safeCropSize = relativeCropSize.clamp(1.0, math.min(
      childWidth - safeCropX,
      childHeight - safeCropY,
    ));

    // Переводим в пиксели изображения
    final scaleX = _image!.width / childWidth;
    final scaleY = _image!.height / childHeight;
    
    final originalCropX = (safeCropX * scaleX).clamp(0.0, _image!.width.toDouble());
    final originalCropY = (safeCropY * scaleY).clamp(0.0, _image!.height.toDouble());
    
    final originalCropSize = (safeCropSize * scaleX).clamp(1.0, math.min(
       _image!.width - originalCropX,
       _image!.height - originalCropY
    )).toDouble();

    // Создаем canvas для обрезки с учетом поворота и отражения
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Применяем трансформации
    canvas.save();
    
    // Перемещаем в центр
    canvas.translate(cropSize / 2, cropSize / 2);
    
    // Применяем поворот
    if (_rotation != 0) {
      canvas.rotate(_rotation * math.pi / 180);
    }
    
    // Применяем отражение
    if (_flipHorizontal) {
      canvas.scale(-1.0, 1.0);
    }
    if (_flipVertical) {
      canvas.scale(1.0, -1.0);
    }
    
    // Возвращаемся к началу координат
    canvas.translate(-cropSize / 2, -cropSize / 2);
    
    // Рисуем обрезанную область
    canvas.drawImageRect(
      _image!,
      Rect.fromLTWH(originalCropX.toDouble(), originalCropY.toDouble(), originalCropSize, originalCropSize),
      Rect.fromLTWH(0, 0, cropSize, cropSize),
      Paint(),
    );
    
    canvas.restore();

    final picture = recorder.endRecording();
    final croppedImage = await picture.toImage(cropSize.toInt(), cropSize.toInt());
    final byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
    croppedImage.dispose();
    picture.dispose();

    return byteData!.buffer.asUint8List();
  }
  
  void _rotateImage() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
    });
  }
  
  void _flipImageHorizontal() {
    setState(() {
      _flipHorizontal = !_flipHorizontal;
    });
  }
  
  void _flipImageVertical() {
    setState(() {
      _flipVertical = !_flipVertical;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cropSize = size.width - 32; // Оставляем отступы

    // Вычисляем размеры контента для отображения
    double childWidth = cropSize;
    double childHeight = cropSize;
    if (_image != null) {
      final imageAspectRatio = _image!.width / _image!.height;
      if (imageAspectRatio > 1) {
        childHeight = cropSize;
        childWidth = cropSize * imageAspectRatio;
      } else {
        childWidth = cropSize;
        childHeight = cropSize / imageAspectRatio;
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Crop Image',
          style: GoogleFonts.delaGothicOne(
            fontSize: 24,
            color: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final croppedBytes = await _cropImage();
              if (mounted) {
                Navigator.of(context).pop(croppedBytes);
              }
            },
            child: const Text(
              'Done',
              style: TextStyle(
                color: Color(0xFF0095F6),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
              ),
            )
          : _image == null
              ? const Center(
                  child: Text(
                    'Failed to load image',
                    style: TextStyle(color: Colors.white),
                  ),
                )
              : Center(
                  child: SizedBox(
                    width: cropSize,
                    height: cropSize,
                    child: ClipRect(
                      child: Stack(
                  children: [
                    // Интерактивное изображение
                          Transform.rotate(
                      angle: _rotation * math.pi / 180,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..scale(_flipHorizontal ? -1.0 : 1.0, _flipVertical ? -1.0 : 1.0),
                        child: InteractiveViewer(
                          transformationController: _transformationController,
                                minScale: _minScale,
                                maxScale: _maxScale,
                                boundaryMargin: EdgeInsets.zero,
                                constrained: false,
                                clipBehavior: Clip.none,
                          child: SizedBox(
                                  width: childWidth,
                                  height: childHeight,
                            child: CustomPaint(
                              painter: _ImagePainter(_image!),
                            ),
                          ),
                        ),
                      ),
                    ),
                          // Рамка кадрирования (поверх изображения)
                          IgnorePointer(
                            child: CustomPaint(
                              size: Size(cropSize, cropSize),
                              painter: _CropOverlayPainter(),
                            ),
                    ),
                  ],
                      ),
                    ),
                  ),
                ),
      // Кнопки управления под превью
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Кнопка поворота
              _buildControlButton(
                icon: const Icon(
                  EvaIcons.refreshOutline,
                  color: Colors.white,
                  size: 24,
                ),
                label: 'Rotate',
                onTap: _rotateImage,
              ),
              // Кнопка отражения по горизонтали
              _buildControlButton(
                icon: const Icon(
                  EvaIcons.flip2Outline,
                  color: Colors.white,
                  size: 24,
                ),
                label: 'Flip H',
                onTap: _flipImageHorizontal,
              ),
              // Кнопка отражения по вертикали (повернутая на 90 градусов)
              _buildControlButton(
                icon: Transform.rotate(
                  angle: math.pi / 2,
                  child: const Icon(
                    EvaIcons.flip2Outline,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                label: 'Flip V',
                onTap: _flipImageVertical,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildControlButton({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;

  _ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    // Вычисляем размеры для отображения изображения с сохранением пропорций
    final imageAspectRatio = image.width / image.height;
    final sizeAspectRatio = size.width / size.height;

    double drawWidth, drawHeight;
    if (imageAspectRatio > sizeAspectRatio) {
      drawWidth = size.width;
      drawHeight = size.width / imageAspectRatio;
    } else {
      drawHeight = size.height;
      drawWidth = size.height * imageAspectRatio;
    }

    final offsetX = (size.width - drawWidth) / 2;
    final offsetY = (size.height - drawHeight) / 2;

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) => oldDelegate.image != image;
}

class _CropOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cropRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Рисуем рамку области обрезки
    final borderPaint = Paint()
      ..color = const Color(0xFF0095F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(cropRect, borderPaint);

    // Рисуем угловые маркеры
    final cornerLength = 20.0;
    final cornerPaint = Paint()
      ..color = const Color(0xFF0095F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Левый верхний угол
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top),
      Offset(cropRect.left + cornerLength, cropRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top),
      Offset(cropRect.left, cropRect.top + cornerLength),
      cornerPaint,
    );

    // Правый верхний угол
    canvas.drawLine(
      Offset(cropRect.right, cropRect.top),
      Offset(cropRect.right - cornerLength, cropRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.top),
      Offset(cropRect.right, cropRect.top + cornerLength),
      cornerPaint,
    );

    // Левый нижний угол
    canvas.drawLine(
      Offset(cropRect.left, cropRect.bottom),
      Offset(cropRect.left + cornerLength, cropRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.bottom),
      Offset(cropRect.left, cropRect.bottom - cornerLength),
      cornerPaint,
    );

    // Правый нижний угол
    canvas.drawLine(
      Offset(cropRect.right, cropRect.bottom),
      Offset(cropRect.right - cornerLength, cropRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.bottom),
      Offset(cropRect.right, cropRect.bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) => false;
}

