import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/news_provider.dart';
import '../models/news.dart';
import '../widgets/app_notification.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../widgets/quill_editor_with_custom_toolbar.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';


class CreateNewsScreen extends StatefulWidget {
  const CreateNewsScreen({super.key});

  @override
  State<CreateNewsScreen> createState() => _CreateNewsScreenState();
}

class _CreateNewsScreenState extends State<CreateNewsScreen> {
  final TextEditingController _titleController = TextEditingController();
  final QuillController _quillController = QuillController.basic();
  final TextEditingController _linkUrlController = TextEditingController();
  final TextEditingController _linkTextController = TextEditingController();
  
  bool _isLoading = false;
  bool _showPreview = false; // Toggle between edit and preview
  bool _isDarkMode = false;
  String? _selectedCategoryId;
  String? _selectedSubcategoryId;
  Uint8List? _coverImageBytes;
  User? _selectedCoauthor;
  List<NewsCategory> _categories = [];
  List<NewsSubcategory> _subcategories = [];

  // Track active formatting states
  bool _isBoldActive = false;
  bool _isItalicActive = false;
  bool _isHeaderActive = false;
  bool _isHeader2Active = false;
  bool _isQuoteActive = false;
  bool _isLinkActive = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
    // Load categories after first frame to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategories();
    });
    // Listen to selection changes to update toolbar states
    _quillController.addListener(_onSelectionChanged);
  }


  void _onSelectionChanged() {
    // Update formatting states based on current selection
    final selection = _quillController.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final style = _quillController.getSelectionStyle();
      setState(() {
        _isBoldActive = style.attributes.containsKey('bold');
        _isItalicActive = style.attributes.containsKey('italic');
        _isHeaderActive = style.attributes.containsKey('header') &&
                         style.attributes['header']?.value == 1;
        _isHeader2Active = style.attributes.containsKey('header') &&
                          style.attributes['header']?.value == 2;
        _isQuoteActive = style.attributes.containsKey('blockquote');
        _isLinkActive = style.attributes.containsKey('link');
      });
    }
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    await prefs.setBool('is_dark_mode', _isDarkMode);
  }

  Future<void> _loadCategories() async {
    if (!mounted) return;
    
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    
    if (!mounted) return;
    final newsProvider = Provider.of<NewsProvider>(context, listen: false);
    
    if (accessToken != null) {
      await newsProvider.loadCategories(accessToken: accessToken);
      if (mounted) {
        setState(() {
          _categories = newsProvider.categories;
        });
      }
    }
  }

  void _onCategoryChanged(String? categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
      _selectedSubcategoryId = null;
      if (categoryId != null) {
        final newsProvider = Provider.of<NewsProvider>(context, listen: false);
        _subcategories = newsProvider.subcategoriesByCategory[categoryId] ?? [];
      } else {
        _subcategories = [];
      }
    });
  }

  Future<void> _pickCoverImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _coverImageBytes = bytes;
      });
    }
  }

  Future<void> _insertImageIntoArticle() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      final bytes = await image.readAsBytes();
      
      setState(() {
        _isLoading = true;
      });

      try {
        final apiService = ApiService();
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        if (accessToken != null) {
          apiService.setAccessToken(accessToken);
        }

        final mediaUrl = await apiService.uploadMedia(
          fileBytes: bytes,
          fileName: 'article_img_${DateTime.now().millisecondsSinceEpoch}.jpg',
          mediaType: 'image',
        );

        if (mediaUrl != null && mounted) {
          int index = _quillController.selection.baseOffset;
          int length = _quillController.selection.extentOffset - index;
          if (index < 0) {
            index = _quillController.document.length - 1;
            if (index < 0) index = 0;
            length = 0;
          }
          _quillController.document.insert(index, BlockEmbed.image(mediaUrl));
          // Move cursor after the image
          _quillController.updateSelection(TextSelection.collapsed(offset: index + 1), ChangeSource.local);
        }
      } catch (e) {
        if (mounted) {
          AppNotification.showError(context, 'Failed to upload image: $e');
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

  Future<void> _showUserSearch() async {
    final TextEditingController searchController = TextEditingController();
    List<User> searchResults = [];
    bool isSearching = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Search user',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Username or name',
                        hintStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF262626)),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF262626),
                      ),
                      onChanged: (value) async {
                        if (value.trim().isEmpty) {
                          setModalState(() {
                            searchResults = [];
                            isSearching = false;
                          });
                          return;
                        }

                        setModalState(() {
                          isSearching = true;
                        });

                        try {
                          final apiService = ApiService();
                          final prefs = await SharedPreferences.getInstance();
                          final accessToken = prefs.getString('access_token');
                          if (accessToken != null) {
                            apiService.setAccessToken(accessToken);
                          }
                          final users = await apiService.searchUsers(value.trim());
                          setModalState(() {
                            searchResults = users;
                            isSearching = false;
                          });
                        } catch (e) {
                          setModalState(() {
                            searchResults = [];
                            isSearching = false;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    if (isSearching)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      )
                    else if (searchResults.isEmpty && searchController.text.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'No users found',
                          style: TextStyle(color: Color(0xFF8E8E8E)),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final user = searchResults[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: user.avatarUrl != null
                                    ? NetworkImage(user.avatarUrl!)
                                    : null,
                                child: user.avatarUrl == null
                                    ? const Icon(EvaIcons.personOutline, color: Colors.white)
                                    : null,
                              ),
                              title: Text(
                                user.username,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                user.name,
                                style: const TextStyle(color: Color(0xFF8E8E8E)),
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedCoauthor = user;
                                });
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showExternalLinkDialog() async {
    final TextEditingController urlController = TextEditingController(text: _linkUrlController.text);
    final TextEditingController textController = TextEditingController(text: _linkTextController.text);

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'External link',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'URL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'https://example.com',
                        hintStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF262626)),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF262626),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Button text',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: textController,
                      maxLength: 8,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '6-8 characters',
                        hintStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF262626)),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF262626),
                        counterText: '${textController.text.length}/8',
                        counterStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                      ),
                      onChanged: (value) {
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Container(
                        width: 200,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0095F6),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0095F6).withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () {
                              setState(() {
                                _linkUrlController.text = urlController.text;
                                _linkTextController.text = textController.text;
                              });
                              Navigator.pop(context);
                            },
                            child: const Center(
                              child: Text(
                                'Next',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _uploadCoverImage() async {
    if (_coverImageBytes == null) return null;

    try {
      final apiService = ApiService();
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken != null) {
        apiService.setAccessToken(accessToken);
      }

      // Upload as image
      final mediaUrl = await apiService.uploadMedia(
        fileBytes: _coverImageBytes!,
        fileName: 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg',
        mediaType: 'image',
      );

      return mediaUrl;
    } catch (e) {
      print('Error uploading cover image: $e');
      return null;
    }
  }

  Future<void> _createNews() async {
    if (_titleController.text.trim().isEmpty) {
      AppNotification.showError(context, 'Title is required');
      return;
    }

    if (_selectedCategoryId == null) {
      AppNotification.showError(context, 'Category is required');
      return;
    }

    final deltaJson = _quillController.document.toDelta().toJson();
    final converter = QuillDeltaToHtmlConverter(
      List.castFrom(deltaJson),
      ConverterOptions.forEmail(),
    );
    final html = converter.convert();
    
    // Fallback to check if content is actually empty (stripping html tags)
    final plainText = _quillController.document.toPlainText();
    if (plainText.trim().isEmpty && !html.contains('<img')) {
      AppNotification.showError(context, 'Content is required');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      final newsProvider = Provider.of<NewsProvider>(context, listen: false);

      // Upload cover image if exists
      String? coverImageUrl;
      if (_coverImageBytes != null) {
        coverImageUrl = await _uploadCoverImage();
      }

      // Prepare coauthors
      List<String>? coauthors;
      if (_selectedCoauthor != null) {
        coauthors = [_selectedCoauthor!.username];
      }

      await newsProvider.createNews(
        title: _titleController.text.trim(),
        content: html, // HTML generated from Quill Delta
        categoryId: _selectedCategoryId!,
        subcategoryId: _selectedSubcategoryId,
        coverImageUrl: coverImageUrl,
        coauthors: coauthors,
        externalLinkUrl: _linkUrlController.text.trim().isNotEmpty
            ? _linkUrlController.text.trim()
            : null,
        externalLinkText: _linkTextController.text.trim().isNotEmpty
            ? _linkTextController.text.trim()
            : null,
        accessToken: accessToken,
      );

      if (mounted) {
        AppNotification.showSuccess(context, 'News created successfully');
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        AppNotification.showError(context, 'Failed to create news: $e');
      }
    }
  }

  // Toggle formatting methods
  void _toggleBold() {
    _quillController.formatSelection(_isBoldActive ? Attribute.clone(Attribute.bold, null) : BoldAttribute());
  }

  void _toggleItalic() {
    _quillController.formatSelection(_isItalicActive ? Attribute.clone(Attribute.italic, null) : ItalicAttribute());
  }

  void _toggleHeader() {
    _quillController.formatSelection(_isHeaderActive ? Attribute.clone(Attribute.header, null) : HeaderAttribute());
  }

  void _toggleHeader2() {
    _quillController.formatSelection(_isHeader2Active ? Attribute.clone(Attribute.header, null) : HeaderAttribute(level: 2));
  }

  void _toggleQuote() {
    // For blockquote, use the standard formatSelection which should toggle automatically
    _quillController.formatSelection(BlockQuoteAttribute());
  }

  void _handleLinkAction() {
    final selection = _quillController.selection;
    if (selection.isValid && !selection.isCollapsed) {
      // Если есть выделенный текст, показать диалог для ссылки
      _showLinkDialog();
    } else {
      // Если нет выделенного текста, показать диалог внешней ссылки новости
      _showExternalLinkDialog();
    }
  }

  Future<void> _showLinkDialog() async {
    final TextEditingController urlController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Add Link',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'https://example.com',
                        hintStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF262626)),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF262626),
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Container(
                        width: 200,
                        height: 56,
                        decoration: BoxDecoration(
                          color: urlController.text.trim().isNotEmpty
                              ? const Color(0xFF0095F6)
                              : const Color(0xFF8E8E8E),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: urlController.text.trim().isNotEmpty
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF0095F6).withOpacity(0.3),
                                    blurRadius: 12,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: urlController.text.trim().isNotEmpty
                                ? () {
                                    final url = urlController.text.trim();
                                    if (url.isNotEmpty) {
                                      _quillController.formatSelection(LinkAttribute(url));
                                    }
                                    Navigator.pop(context);
                                  }
                                : null,
                            child: const Center(
                              child: Text(
                                'Add Link',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool get _canCreate {
    return _titleController.text.trim().isNotEmpty &&
        _selectedCategoryId != null &&
        _quillController.document.toPlainText().trim().isNotEmpty &&
        !_isLoading;
  }

  @override
  Widget build(BuildContext context) {
    if (_showPreview) {
      return _buildPreviewScreen();
    }
    return _buildEditScreen();
  }

  Widget _buildEditScreen() {
    // Build theme based on _isDarkMode
    final theme = _isDarkMode 
        ? ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Colors.grey[900],
            fontFamily: 'Times New Roman',
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.grey[900],
              elevation: 0,
              titleTextStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                fontFamily: 'Times New Roman',
              ),
              iconTheme: const IconThemeData(color: Colors.white70),
            ),
            colorScheme: ColorScheme.fromSwatch(
              primarySwatch: Colors.blue,
              brightness: Brightness.dark,
            ).copyWith(
              primary: const Color(0xFF3390EC),
              secondary: const Color(0xFF3390EC),
              surface: Colors.grey[850],
              onSurface: Colors.white70,
            ),
            textTheme: const TextTheme(
              displayLarge: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.2,
                fontFamily: 'Times New Roman',
              ),
              bodyLarge: TextStyle(
                fontSize: 18,
                color: Colors.white70,
                height: 1.6,
                fontFamily: 'Times New Roman',
              ),
              labelLarge: TextStyle(
                color: Color(0xFF3390EC),
                fontFamily: 'Times New Roman',
              ),
            ),
            inputDecorationTheme: const InputDecorationTheme(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintStyle: TextStyle(
                fontFamily: 'Times New Roman',
                color: Colors.grey,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white70),
          )
        : ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF4F4F4),
            fontFamily: 'Times New Roman',
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 0,
              titleTextStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
                fontFamily: 'Times New Roman',
              ),
              iconTheme: IconThemeData(color: Colors.black54),
            ),
            colorScheme: ColorScheme.fromSwatch(
              primarySwatch: Colors.blue,
              brightness: Brightness.light,
            ).copyWith(
              primary: const Color(0xFF3390EC),
              secondary: const Color(0xFF3390EC),
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            textTheme: const TextTheme(
              displayLarge: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
                height: 1.2,
                fontFamily: 'Times New Roman',
              ),
              bodyLarge: TextStyle(
                fontSize: 18,
                color: Colors.black87,
                height: 1.6,
                fontFamily: 'Times New Roman',
              ),
              labelLarge: TextStyle(
                color: Color(0xFF3390EC),
                fontFamily: 'Times New Roman',
              ),
            ),
            inputDecorationTheme: const InputDecorationTheme(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintStyle: TextStyle(
                fontFamily: 'Times New Roman',
                color: Color(0xFFBBBBBB),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.black54),
          );

    return Theme(
      data: theme,
      child: Builder(
        builder: (themeContext) => Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    // App bar точно как в тз.txt
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: theme.appBarTheme.backgroundColor,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            offset: const Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                color: theme.iconTheme.color,
                                onPressed: () => Navigator.pop(context),
                              ),
                              Text(
                                'Create news',
                                style: theme.appBarTheme.titleTextStyle,
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: _titleController.text.trim().isNotEmpty && 
                                       _quillController.document.toPlainText().trim().isNotEmpty
                                ? () => setState(() => _showPreview = true)
                                : null,
                            child: Text(
                              'NEXT',
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Content area точно как в тз.txt
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Column(
                            children: [
                              const SizedBox(height: 40),
                              TextField(
                                controller: _titleController,
                                style: theme.textTheme.displayLarge,
                                decoration: InputDecoration(
                                  hintText: 'Title',
                                  hintStyle: theme.inputDecorationTheme.hintStyle?.copyWith(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                maxLines: null,
                                textCapitalization: TextCapitalization.sentences,
                              ),
                              const SizedBox(height: 32),
                              QuillEditorWithCustomSelectionToolbar(
                                quillController: _quillController,
                              ),
                              const SizedBox(height: 100),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Bottom toolbar точно как в тз.txt
                    Container(
                      height: 64,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, -1),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildToolbarIconButton(
                      icon: Icons.title,
                      label: 'Title',
                      iconColor: _isHeaderActive ? const Color(0xFF0095F6) : theme.iconTheme.color!,
                      onPressed: () => _toggleHeader(),
                    ),
                    _buildToolbarIconButton(
                      icon: Icons.subtitles,
                      label: 'Subtitle',
                      iconColor: _isHeader2Active ? const Color(0xFF0095F6) : theme.iconTheme.color!,
                      onPressed: () => _toggleHeader2(),
                    ),
                    _buildToolbarIconButton(
                      icon: Icons.format_bold,
                      label: 'Bold',
                      iconColor: _isBoldActive ? const Color(0xFF0095F6) : theme.iconTheme.color!,
                      onPressed: () => _toggleBold(),
                    ),
                    _buildToolbarIconButton(
                      icon: Icons.format_italic,
                      label: 'Italic',
                      iconColor: _isItalicActive ? const Color(0xFF0095F6) : theme.iconTheme.color!,
                      onPressed: () => _toggleItalic(),
                    ),
                    _buildToolbarIconButton(
                      icon: Icons.link,
                      label: 'Link',
                      iconColor: _isLinkActive ? const Color(0xFF0095F6) : theme.iconTheme.color!,
                      onPressed: () => _handleLinkAction(),
                    ),
                    _buildToolbarIconButton(
                      icon: Icons.format_quote,
                      label: 'Quote',
                      iconColor: _isQuoteActive ? const Color(0xFF0095F6) : theme.iconTheme.color!,
                      onPressed: () => _toggleQuote(),
                    ),
                    _buildToolbarIconButton(
                      icon: Icons.image,
                      label: 'Image',
                      iconColor: theme.iconTheme.color!,
                      onPressed: _insertImageIntoArticle,
                    ),
                  ],
                ),
              ),
            ),
              ],
            ),
            // Floating theme toggle button
            Positioned(
              left: 16,
              bottom: 80,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: theme.colorScheme.surface,
                onPressed: _toggleTheme,
                child: Icon(
                  _isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  color: theme.iconTheme.color,
                ),
              ),
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildPreviewScreen() {

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBackOutline, color: Colors.white),
          onPressed: () {
            setState(() {
              _showPreview = false;
            });
          },
        ),
        title: const Text(
          'Preview',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Category selector
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF262626)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Category',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _selectedCategoryId,
                            decoration: InputDecoration(
                              labelText: 'Select category',
                              labelStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF262626)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF262626)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF0095F6)),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF262626),
                            ),
                            dropdownColor: const Color(0xFF1A1A1A),
                            style: const TextStyle(color: Colors.white),
                            items: _categories.map((category) {
                              return DropdownMenuItem<String>(
                                value: category.id,
                                child: Text(category.nameEn),
                              );
                            }).toList(),
                            onChanged: _onCategoryChanged,
                          ),
                          if (_subcategories.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: _selectedSubcategoryId,
                              decoration: InputDecoration(
                                labelText: 'Subcategory (optional)',
                                labelStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF262626)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF262626)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF0095F6)),
                                ),
                                filled: true,
                                fillColor: const Color(0xFF262626),
                              ),
                              dropdownColor: const Color(0xFF1A1A1A),
                              style: const TextStyle(color: Colors.white),
                              items: _subcategories.map((subcategory) {
                                return DropdownMenuItem<String>(
                                  value: subcategory.id,
                                  child: Text(subcategory.nameEn),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedSubcategoryId = value;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Preview news card
                    _buildNewsPreviewCard(),
                    
                    const SizedBox(height: 16),
                    
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showExternalLinkDialog,
                            icon: const Icon(EvaIcons.externalLinkOutline, color: Color(0xFF0095F6)),
                            label: Text(
                              _linkUrlController.text.isNotEmpty
                                  ? 'Edit link'
                                  : 'Add link',
                              style: const TextStyle(color: Color(0xFF0095F6)),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF262626)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showUserSearch,
                            icon: const Icon(EvaIcons.peopleOutline, color: Color(0xFF0095F6)),
                            label: Text(
                              _selectedCoauthor != null
                                  ? 'Edit coauthor'
                                  : 'Add coauthor',
                              style: const TextStyle(color: Color(0xFF0095F6)),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF262626)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickCoverImage,
                        icon: const Icon(EvaIcons.imageOutline, color: Color(0xFF0095F6)),
                        label: Text(
                          _coverImageBytes != null ? 'Change cover image' : 'Add cover image',
                          style: const TextStyle(color: Color(0xFF0095F6)),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF262626)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Publish button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                border: Border(
                  top: BorderSide(color: const Color(0xFF262626)),
                ),
              ),
              child: SafeArea(
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _canCreate
                        ? const Color(0xFF0095F6)
                        : const Color(0xFF8E8E8E),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: _canCreate
                        ? [
                            BoxShadow(
                              color: const Color(0xFF0095F6).withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _canCreate && !_isLoading ? _createNews : null,
                      child: Center(
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'Publish',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsPreviewCard() {
    final title = _titleController.text.trim();
    final content = _quillController.document.toPlainText();
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF262626),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cover image
          if (_coverImageBytes != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.memory(
                _coverImageBytes!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category
                if (_selectedCategoryId != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _categories.firstWhere((c) => c.id == _selectedCategoryId).nameEn,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (_selectedCategoryId != null) const SizedBox(height: 12),
                
                // Title
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                
                // Content preview
                Text(
                  content.length > 150
                      ? '${content.substring(0, 150)}...'
                      : content,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                
                // Coauthor info
                if (_selectedCoauthor != null)
                  Row(
                    children: [
                      const Icon(EvaIcons.peopleOutline, size: 16, color: Color(0xFF8E8E8E)),
                      const SizedBox(width: 4),
                      Text(
                        'Coauthor: ${_selectedCoauthor!.username}',
                        style: const TextStyle(
                          color: Color(0xFF8E8E8E),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                
                // External link
                if (_linkUrlController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF262626),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF0095F6)),
                      ),
                      child: Row(
                        children: [
                          const Icon(EvaIcons.externalLinkOutline, size: 16, color: Color(0xFF0095F6)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _linkTextController.text.isNotEmpty
                                  ? _linkTextController.text
                                  : 'External link',
                              style: const TextStyle(
                                color: Color(0xFF0095F6),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
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
    );
  }

  Widget _buildToolbarIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color iconColor,
  }) {
    return IconButton(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
      icon: Icon(icon, color: iconColor),
      tooltip: label,
      onPressed: onPressed,
    );
  }

  @override
  void dispose() {
    _quillController.removeListener(_onSelectionChanged);
    _titleController.dispose();
    _quillController.dispose();
    _linkUrlController.dispose();
    _linkTextController.dispose();
    super.dispose();
  }
}

