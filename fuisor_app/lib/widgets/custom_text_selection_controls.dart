import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

class CustomQuillTextSelectionControls extends TextSelectionControls {
  final QuillController quillController;

  CustomQuillTextSelectionControls({required this.quillController});

  @override
  Widget buildToolbar(
    BuildContext context,
    Rect globalEditableRegion,
    double textLineHeight,
    Offset selectionMidpoint,
    List<TextSelectionPoint> endpoints,
    TextSelectionDelegate delegate,
    ValueListenable<ClipboardStatus>? clipboardStatus,
    Offset? lastSecondaryTapDownPosition,
  ) {
    return _CustomTextSelectionToolbar(
      quillController: quillController,
      clipboardStatus: clipboardStatus,
      delegate: delegate,
      endpoints: endpoints,
      globalEditableRegion: globalEditableRegion,
      handleCut: canCut(delegate) ? () => handleCut(delegate) : null,
      handleCopy: canCopy(delegate) ? () => handleCopy(delegate) : null,
      handlePaste: canPaste(delegate) ? () => handlePaste(delegate) : null,
      handleSelectAll: canSelectAll(delegate) ? () => handleSelectAll(delegate) : null,
      selectionMidpoint: selectionMidpoint,
      textLineHeight: textLineHeight,
      lastSecondaryTapDownPosition: lastSecondaryTapDownPosition,
    );
  }

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    return CupertinoTextSelectionControls().buildHandle(
      context,
      type,
      textLineHeight,
      onTap,
    );
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    return CupertinoTextSelectionControls().getHandleAnchor(type, textLineHeight);
  }

  @override
  Size getHandleSize(double textLineHeight) {
    return CupertinoTextSelectionControls().getHandleSize(textLineHeight);
  }
}

class _CustomTextSelectionToolbar extends StatelessWidget {
  const _CustomTextSelectionToolbar({
    required this.quillController,
    required this.clipboardStatus,
    required this.delegate,
    required this.endpoints,
    required this.globalEditableRegion,
    this.handleCut,
    this.handleCopy,
    this.handlePaste,
    this.handleSelectAll,
    required this.selectionMidpoint,
    required this.textLineHeight,
    this.lastSecondaryTapDownPosition,
  });

  final QuillController quillController;
  final ValueListenable<ClipboardStatus>? clipboardStatus;
  final TextSelectionDelegate delegate;
  final List<TextSelectionPoint> endpoints;
  final Rect globalEditableRegion;
  final VoidCallback? handleCut;
  final VoidCallback? handleCopy;
  final VoidCallback? handlePaste;
  final VoidCallback? handleSelectAll;
  final Offset selectionMidpoint;
  final double textLineHeight;
  final Offset? lastSecondaryTapDownPosition;

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = [];

    // Standard actions
    if (handleCut != null) {
      items.add(
        CupertinoTextSelectionToolbarButton.text(
          onPressed: handleCut!,
          text: 'Cut',
        ),
      );
    }
    if (handleCopy != null) {
      items.add(
        CupertinoTextSelectionToolbarButton.text(
          onPressed: handleCopy!,
          text: 'Copy',
        ),
      );
    }
    if (handlePaste != null) {
      items.add(
        CupertinoTextSelectionToolbarButton.text(
          onPressed: handlePaste!,
          text: 'Paste',
        ),
      );
    }
    if (handleSelectAll != null) {
      items.add(
        CupertinoTextSelectionToolbarButton.text(
          onPressed: handleSelectAll!,
          text: 'Select All',
        ),
      );
    }

    // Formatting actions
    items.add(
      CupertinoTextSelectionToolbarButton.text(
        onPressed: () {
          quillController.formatSelection(BoldAttribute());
          delegate.hideToolbar();
        },
        text: 'Bold',
      ),
    );
    items.add(
      CupertinoTextSelectionToolbarButton.text(
        onPressed: () {
          quillController.formatSelection(ItalicAttribute());
          delegate.hideToolbar();
        },
        text: 'Italic',
      ),
    );
    items.add(
      CupertinoTextSelectionToolbarButton.text(
        onPressed: () {
          quillController.formatSelection(UnderlineAttribute());
          delegate.hideToolbar();
        },
        text: 'Underline',
      ),
    );

    // Calculate anchor positions
    final anchorAbove = Offset(
      selectionMidpoint.dx,
      selectionMidpoint.dy - textLineHeight,
    );
    final anchorBelow = Offset(
      selectionMidpoint.dx,
      selectionMidpoint.dy + textLineHeight,
    );

    return CupertinoTextSelectionToolbar(
      anchorAbove: anchorAbove,
      anchorBelow: anchorBelow,
      children: items,
    );
  }
}

