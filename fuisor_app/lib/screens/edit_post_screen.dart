import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../providers/posts_provider.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

class EditPostScreen extends StatefulWidget {
  final String postId;
  final String currentCaption;
  final User? currentCoauthor;
  final String? currentExternalLinkUrl;
  final String? currentExternalLinkText;

  const EditPostScreen({
    Key? key,
    required this.postId,
    required this.currentCaption,
    this.currentCoauthor,
    this.currentExternalLinkUrl,
    this.currentExternalLinkText,
  }) : super(key: key);

  @override
  State<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  final _captionController = TextEditingController();
  final _linkUrlController = TextEditingController();
  final _linkTextController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  User? _selectedCoauthor;

  @override
  void initState() {
    super.initState();
    _captionController.text = widget.currentCaption;
    _selectedCoauthor = widget.currentCoauthor;
    _linkUrlController.text = widget.currentExternalLinkUrl ?? '';
    _linkTextController.text = widget.currentExternalLinkText ?? '';
  }

  @override
  void dispose() {
    _captionController.dispose();
    _linkUrlController.dispose();
    _linkTextController.dispose();
    super.dispose();
  }

  Future<String?> _getAccessTokenFromAuthProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('access_token');
    } catch (e) {
      print('Error getting access token: $e');
      return null;
    }
  }

  Future<void> _updatePost() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final accessToken = await _getAccessTokenFromAuthProvider();
      if (accessToken == null) {
        throw Exception('No access token found');
      }

      // Validate external link fields
      String? linkUrl;
      String? linkText;
      
      linkUrl = _linkUrlController.text.trim();
      linkText = _linkTextController.text.trim();
      
      if (linkUrl.isNotEmpty) {
        // Add https:// if no protocol specified
        if (!linkUrl.startsWith('http://') && !linkUrl.startsWith('https://')) {
          linkUrl = 'https://$linkUrl';
        }
        
        // Validate URL
        final uri = Uri.tryParse(linkUrl);
        if (uri == null || !uri.hasAbsolutePath) {
          throw Exception('Invalid URL format');
        }
        
        // Validate link text length
        if (linkText.isNotEmpty && (linkText.length < 6 || linkText.length > 8)) {
          throw Exception('Button text must be 6-8 characters');
        }
      }

      final postsProvider = context.read<PostsProvider>();
      await postsProvider.updatePost(
        postId: widget.postId,
        caption: _captionController.text.trim(),
        accessToken: accessToken,
        coauthor: _selectedCoauthor?.id,
        externalLinkUrl: linkUrl.isNotEmpty ? linkUrl : null,
        externalLinkText: linkText.isNotEmpty ? linkText : null,
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Show user search dialog
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
          builder: (context, setState) {
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
                      'Search Coauthor',
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
                      decoration: const InputDecoration(
                        hintText: 'Search by username...',
                        hintStyle: TextStyle(color: Color(0xFF8E8E8E)),
                        prefixIcon: Icon(EvaIcons.search, color: Color(0xFF8E8E8E)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        filled: true,
                        fillColor: Color(0xFF262626),
                      ),
                      onChanged: (value) async {
                        if (value.length >= 2) {
                          setState(() {
                            isSearching = true;
                          });
                          
                          try {
                            final token = await _getAccessTokenFromAuthProvider();
                            if (token != null) {
                              final apiService = ApiService();
                              apiService.setAccessToken(token);
                              final results = await apiService.searchUsers(value, limit: 10);
                              
                              setState(() {
                                searchResults = results;
                                isSearching = false;
                              });
                            }
                          } catch (e) {
                            print('Error searching users: $e');
                            setState(() {
                              isSearching = false;
                            });
                          }
                        } else {
                          setState(() {
                            searchResults = [];
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    if (isSearching)
                      const CircularProgressIndicator(
                        color: Color(0xFF0095F6),
                      )
                    else if (searchResults.isNotEmpty)
                      SizedBox(
                        height: 300,
                        child: ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final user = searchResults[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: user.avatarUrl != null
                                    ? NetworkImage(user.avatarUrl!)
                                    : null,
                                child: user.avatarUrl == null
                                    ? const Icon(EvaIcons.personOutline)
                                    : null,
                              ),
                              title: Text(
                                user.name,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '@${user.username}',
                                style: const TextStyle(color: Color(0xFF8E8E8E)),
                              ),
                              onTap: () {
                                this.setState(() {
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

  // Show external link bottom sheet
  Future<void> _showExternalLinkSheet() async {
    final TextEditingController urlController = TextEditingController(text: _linkUrlController.text);
    final TextEditingController textController = TextEditingController(text: _linkTextController.text);

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'External Link',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(EvaIcons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Link URL',
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
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://example.com',
                      hintStyle: TextStyle(color: Color(0xFF8E8E8E)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: Color(0xFF262626)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: Color(0xFF262626)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: Color(0xFF0095F6)),
                      ),
                      filled: true,
                      fillColor: Color(0xFF262626),
                      prefixIcon: Icon(EvaIcons.link, color: Color(0xFF8E8E8E)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Button Text',
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
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: Color(0xFF262626)),
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: Color(0xFF262626)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: Color(0xFF0095F6)),
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
                  const SizedBox(height: 8),
                  const Text(
                    'Button text will be displayed on the post',
                    style: TextStyle(
                      color: Color(0xFF8E8E8E),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0095F6),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _linkUrlController.text = urlController.text;
                          _linkTextController.text = textController.text;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Edit Post',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _updatePost,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: Color(0xFF0095F6),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Caption',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _captionController,
                maxLines: 5,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Write a caption...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Color(0xFF0095F6)),
                  ),
                  filled: true,
                  fillColor: Color(0xFF1C1C1E),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Caption cannot be empty';
                  }
                  return null;
                },
              ),
              
              // Coauthor section
              const SizedBox(height: 24),
              const Text(
                'Coauthor',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (_selectedCoauthor != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage: _selectedCoauthor!.avatarUrl != null
                            ? NetworkImage(_selectedCoauthor!.avatarUrl!)
                            : null,
                        child: _selectedCoauthor!.avatarUrl == null
                            ? const Icon(EvaIcons.personOutline, size: 20)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedCoauthor!.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '@${_selectedCoauthor!.username}',
                              style: const TextStyle(
                                color: Color(0xFF8E8E8E),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(EvaIcons.close, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _selectedCoauthor = null;
                          });
                        },
                      ),
                    ],
                  ),
                )
              else
                GestureDetector(
                  onTap: () => _showUserSearch(),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF404040),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(EvaIcons.personAddOutline, color: Color(0xFF8E8E8E)),
                        SizedBox(width: 12),
                        Text(
                          'Add coauthor (optional)',
                          style: TextStyle(color: Color(0xFF8E8E8E)),
                        ),
                      ],
                    ),
                  ),
                ),
              
              // External link section
              const SizedBox(height: 24),
              const Text(
                'External Link',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showExternalLinkSheet(),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _linkUrlController.text.isNotEmpty 
                          ? const Color(0xFF0095F6)
                          : const Color(0xFF404040),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        EvaIcons.link,
                        color: _linkUrlController.text.isNotEmpty 
                            ? const Color(0xFF0095F6)
                            : const Color(0xFF8E8E8E),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _linkUrlController.text.isNotEmpty
                              ? _linkTextController.text.isNotEmpty
                                  ? '${_linkTextController.text} • ${_linkUrlController.text}'
                                  : _linkUrlController.text
                              : 'Add external link (optional)',
                          style: TextStyle(
                            color: _linkUrlController.text.isNotEmpty
                                ? Colors.white
                                : const Color(0xFF8E8E8E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_linkUrlController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(EvaIcons.close, color: Colors.white, size: 20),
                          onPressed: () {
                            setState(() {
                              _linkUrlController.clear();
                              _linkTextController.clear();
                            });
                          },
                        )
                      else
                        const Icon(EvaIcons.arrowIosForward, color: Color(0xFF8E8E8E)),
                    ],
                  ),
                ),
              ),
              
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(EvaIcons.alertCircle, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
