import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

/// HTML sanitization service for Flutter
/// Sanitizes HTML content to prevent XSS attacks
class HtmlSanitizerService {
  /// Allowed HTML tags
  static const List<String> _allowedTags = [
    'p', 'br', 'strong', 'em', 'u', 'b', 'i',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'ul', 'ol', 'li', 'a', 'blockquote',
  ];

  /// Allowed attributes for specific tags
  static const Map<String, List<String>> _allowedAttributes = {
    'a': ['href', 'title', 'target'],
  };

  /// Allowed URL schemes
  static const List<String> _allowedSchemes = ['http', 'https', 'mailto'];

  /// Sanitizes HTML content, allowing only safe tags and attributes
  /// 
  /// Allowed tags: p, br, strong, em, u, b, i, h1-h6, ul, ol, li, a, blockquote
  /// Strips dangerous tags: script, iframe, object, embed, form
  /// Sanitizes attributes (only href for links, no javascript:)
  /// Removes event handlers
  static String sanitizeHtml(String html) {
    if (html.isEmpty) {
      return '';
    }

    try {
      final document = html_parser.parse(html);
      _sanitizeNode(document);
      return document.body?.innerHtml ?? '';
    } catch (e) {
      // If sanitization fails, return empty string for safety
      return '';
    }
  }

  /// Recursively sanitize DOM nodes
  static void _sanitizeNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      // Remove dangerous tags
      if (!_allowedTags.contains(node.localName?.toLowerCase())) {
        node.remove();
        return;
      }

      // Sanitize attributes
      final allowedAttrs = _allowedAttributes[node.localName?.toLowerCase()] ?? [];
      final attrsToRemove = <String>[];
      
      node.attributes.forEach((key, value) {
        final keyStr = key.toString();
        final valueStr = value.toString();
        
        // Remove event handlers
        if (keyStr.startsWith('on')) {
          attrsToRemove.add(keyStr);
          return;
        }

        // Check if attribute is allowed
        if (!allowedAttrs.contains(keyStr.toLowerCase())) {
          attrsToRemove.add(keyStr);
          return;
        }

        // Sanitize href attributes
        if (keyStr.toLowerCase() == 'href') {
          final lowerValue = valueStr.toLowerCase();
          // Remove javascript: and data: URLs
          if (lowerValue.startsWith('javascript:') || lowerValue.startsWith('data:')) {
            attrsToRemove.add(keyStr);
            return;
          }
          // Check allowed schemes
          final hasAllowedScheme = _allowedSchemes.any((scheme) => 
            lowerValue.startsWith('$scheme:'));
          if (!hasAllowedScheme && !lowerValue.startsWith('/') && !lowerValue.startsWith('#')) {
            attrsToRemove.add(keyStr);
            return;
          }
          // Ensure external links have target and rel
          if (valueStr.startsWith('http://') || valueStr.startsWith('https://')) {
            node.attributes['target'] = '_blank';
            node.attributes['rel'] = 'noopener noreferrer';
          }
        }
      });

      // Remove disallowed attributes
      for (final attr in attrsToRemove) {
        node.attributes.remove(attr);
      }

      // Recursively sanitize children
      final children = List<html_dom.Node>.from(node.nodes);
      for (final child in children) {
        _sanitizeNode(child);
      }
    } else if (node is html_dom.Text) {
      // Text nodes are safe, keep them
      return;
    }
  }

  /// Sanitizes HTML and ensures external links open in new tab
  static String sanitizeHtmlForDisplay(String html) {
    String sanitized = sanitizeHtml(html);
    
    // Ensure external links have target="_blank" and rel="noopener noreferrer"
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'<a\s+([^>]*?)href="([^"]*?)"([^>]*?)>', caseSensitive: false),
      (match) {
        String href = match.group(2) ?? '';
        String beforeHref = match.group(1) ?? '';
        String afterHref = match.group(3) ?? '';
        
        // Skip if it's a javascript: or data: URL
        if (href.toLowerCase().startsWith('javascript:') ||
            href.toLowerCase().startsWith('data:')) {
          return '<a>';
        }
        
        // Add target and rel if not present
        String result = '<a $beforeHref href="$href"';
        if (!afterHref.contains('target=')) {
          result += ' target="_blank"';
        }
        if (!afterHref.contains('rel=')) {
          result += ' rel="noopener noreferrer"';
        }
        result += '$afterHref>';
        return result;
      },
    );
    
    return sanitized;
  }
}

