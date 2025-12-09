import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'app_notification.dart';

class AddWebsiteDialog extends StatefulWidget {
  final String? initialUrl;

  const AddWebsiteDialog({
    super.key,
    this.initialUrl,
  });

  @override
  State<AddWebsiteDialog> createState() => _AddWebsiteDialogState();
  
  // Статический метод для показа bottom sheet
  static Future<String?> show(BuildContext context, {String? initialUrl}) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AddWebsiteDialog(initialUrl: initialUrl),
    );
  }
}

class _AddWebsiteDialogState extends State<AddWebsiteDialog> {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;


  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      _urlController.text = widget.initialUrl!;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Пустая ссылка разрешена (для удаления)
    }

    final trimmed = value.trim();
    
    // Проверяем, что это валидный URL
    Uri? uri;
    try {
      // Добавляем https:// если протокол не указан
      final urlWithProtocol = trimmed.startsWith('http://') || trimmed.startsWith('https://')
          ? trimmed
          : 'https://$trimmed';
      uri = Uri.parse(urlWithProtocol);
    } catch (e) {
      return 'Please enter a valid URL';
    }

    if (uri.host.isEmpty) {
      return 'Please enter a valid URL';
    }

    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final url = _urlController.text.trim();
    String? finalUrl;

    if (url.isNotEmpty) {
      // Нормализуем URL (добавляем https:// если нужно)
      final urlWithProtocol = url.startsWith('http://') || url.startsWith('https://')
          ? url
          : 'https://$url';
      
      // Проверяем, что URL валидный
      try {
        final uri = Uri.parse(urlWithProtocol);
        if (uri.host.isNotEmpty) {
          finalUrl = urlWithProtocol;
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          AppNotification.showError(context, 'Invalid URL format');
        }
        return;
      }
    }

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      Navigator.of(context).pop(finalUrl);
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
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.initialUrl != null ? 'Edit link' : 'Add link',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Telegram, YouTube, Twitter, LinkedIn and other websites',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF8E8E8E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          EvaIcons.closeCircleOutline,
                          color: Color(0xFF8E8E8E),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // URL Input Field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TextFormField(
                    controller: _urlController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'https://example.com',
                      hintStyle: const TextStyle(
                        color: Color(0xFF8E8E8E),
                      ),
                      prefixIcon: const Icon(
                        EvaIcons.link2Outline,
                        color: Color(0xFF8E8E8E),
                        size: 20,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF262626),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF404040),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF404040),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF0095F6),
                          width: 2,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.red,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.red,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                    keyboardType: TextInputType.url,
                    validator: _validateUrl,
                    enabled: !_isLoading,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Action buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      // Delete button (only if editing)
                      if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) ...[
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: _isLoading
                                    ? null
                                    : () {
                                        Navigator.of(context).pop('');
                                      },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      EvaIcons.trash2Outline,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Delete',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      // Save/Add button
                      Expanded(
                        flex: widget.initialUrl != null && widget.initialUrl!.isNotEmpty ? 2 : 1,
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: _isLoading
                                ? const Color(0xFF8E8E8E)
                                : const Color(0xFF0095F6),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: _isLoading
                                ? []
                                : [
                                    BoxShadow(
                                      color: const Color(0xFF0095F6).withOpacity(0.3),
                                      blurRadius: 12,
                                      spreadRadius: 0,
                                      offset: const Offset(0, 4),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: _isLoading ? null : _save,
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            EvaIcons.checkmark,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            widget.initialUrl != null && widget.initialUrl!.isNotEmpty
                                                ? 'Save'
                                                : 'Add',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

