import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

class QuillEditorWithCustomSelectionToolbar extends StatefulWidget {
  final QuillController quillController;

  const QuillEditorWithCustomSelectionToolbar({
    super.key,
    required this.quillController,
  });

  @override
  State<QuillEditorWithCustomSelectionToolbar> createState() =>
      _QuillEditorWithCustomSelectionToolbarState();
}

class _QuillEditorWithCustomSelectionToolbarState
    extends State<QuillEditorWithCustomSelectionToolbar> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.copyWith(
          bodyLarge: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontFamily: 'Times New Roman',
            height: 1.6,
          ),
        ),
      ),
      child: QuillEditor.basic(
        controller: widget.quillController,
      ),
    );
  }
}

