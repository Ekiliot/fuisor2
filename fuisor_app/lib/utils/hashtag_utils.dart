import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

class HashtagUtils {
  // Regular expression to find hashtags - поддерживает кириллицу, латиницу, цифры и подчеркивания
  static final RegExp _hashtagRegex = RegExp(r'#[а-яёА-ЯЁa-zA-Z0-9_]+');
  // Regular expression to find usernames - поддерживает кириллицу, латиницу, цифры и подчеркивания
  static final RegExp _usernameRegex = RegExp(r'@[а-яёА-ЯЁa-zA-Z0-9_]+');

  /// Extract hashtags from text
  static List<String> extractHashtags(String text) {
    print('HashtagUtils: Extracting hashtags from: "$text"');
    print('HashtagUtils: Regex pattern: ${_hashtagRegex.pattern}');
    final matches = _hashtagRegex.allMatches(text);
    final hashtags = matches.map((match) => match.group(0)!).toList();
    print('HashtagUtils: Extracted hashtags: $hashtags');
    print('HashtagUtils: Number of matches: ${matches.length}');
    return hashtags;
  }

  /// Parse text and create TextSpan with clickable hashtags
  static List<TextSpan> parseTextWithHashtags(
    String text, {
    TextStyle? defaultStyle,
    TextStyle? hashtagStyle,
    Function(String hashtag)? onHashtagTap,
  }) {
    print('HashtagUtils: Parsing text: "$text"');
    
    final List<TextSpan> spans = [];
    final defaultTextStyle = defaultStyle ?? const TextStyle(color: Colors.white);
    final hashtagTextStyle = hashtagStyle ?? 
        const TextStyle(
          color: Color(0xFF0095F6),
          fontWeight: FontWeight.w600,
        );

    // Extract hashtags first
    final hashtags = extractHashtags(text);
    print('HashtagUtils: Found hashtags: $hashtags');

    if (hashtags.isEmpty) {
      // No hashtags found, return simple text
      spans.add(TextSpan(
        text: text,
        style: defaultTextStyle,
      ));
      return spans;
    }

    // Split text by hashtags and rebuild
    int lastIndex = 0;
    for (final hashtag in hashtags) {
      final hashtagIndex = text.indexOf(hashtag, lastIndex);
      
      // Add text before hashtag
      if (hashtagIndex > lastIndex) {
        final beforeText = text.substring(lastIndex, hashtagIndex);
        if (beforeText.isNotEmpty) {
          spans.add(TextSpan(
            text: beforeText,
            style: defaultTextStyle,
          ));
        }
      }
      
      // Add hashtag
      spans.add(TextSpan(
        text: hashtag,
        style: hashtagTextStyle,
        recognizer: onHashtagTap != null
            ? (TapGestureRecognizer()
              ..onTap = () {
                print('HashtagUtils: Hashtag tapped: $hashtag');
                print('HashtagUtils: Calling onHashtagTap callback');
                try {
                  onHashtagTap(hashtag.substring(1)); // Remove # symbol
                  print('HashtagUtils: onHashtagTap callback completed');
                } catch (e) {
                  print('HashtagUtils: Error in onHashtagTap callback: $e');
                }
              })
            : null,
      ));
      
      lastIndex = hashtagIndex + hashtag.length;
    }
    
    // Add remaining text after last hashtag
    if (lastIndex < text.length) {
      final remainingText = text.substring(lastIndex);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(
          text: remainingText,
          style: defaultTextStyle,
        ));
      }
    }

    print('HashtagUtils: Created ${spans.length} text spans');
    return spans;
  }

  /// Check if text contains hashtags
  static bool hasHashtags(String text) {
    final hasHashtags = _hashtagRegex.hasMatch(text);
    print('HashtagUtils: hasHashtags("$text") = $hasHashtags');
    return hasHashtags;
  }

  /// Clean hashtag (remove # and convert to lowercase)
  static String cleanHashtag(String hashtag) {
    return hashtag.replaceAll('#', '').toLowerCase();
  }

  /// Format hashtag for display (add # and capitalize)
  static String formatHashtag(String hashtag) {
    final cleaned = cleanHashtag(hashtag);
    return '#$cleaned';
  }

  /// Extract usernames from text
  static List<String> extractUsernames(String text) {
    print('HashtagUtils: Extracting usernames from: "$text"');
    final matches = _usernameRegex.allMatches(text);
    final usernames = matches.map((match) => match.group(0)!).toList();
    print('HashtagUtils: Extracted usernames: $usernames');
    return usernames;
  }

  /// Parse text and create TextSpan with clickable hashtags and usernames
  static List<TextSpan> parseTextWithHashtagsAndUsernames(
    String text, {
    TextStyle? defaultStyle,
    TextStyle? hashtagStyle,
    TextStyle? usernameStyle,
    Function(String hashtag)? onHashtagTap,
    Function(String username)? onUsernameTap,
  }) {
    print('HashtagUtils: Parsing text with hashtags and usernames: "$text"');
    
    final List<TextSpan> spans = [];
    final defaultTextStyle = defaultStyle ?? const TextStyle(color: Colors.white);
    final hashtagTextStyle = hashtagStyle ?? 
        const TextStyle(
          color: Color(0xFF0095F6),
          fontWeight: FontWeight.w600,
        );
    final usernameTextStyle = usernameStyle ?? 
        const TextStyle(
          color: Color(0xFF0095F6),
          fontWeight: FontWeight.w600,
        );

    // Find all matches (hashtags and usernames) with their positions
    final List<_MatchInfo> matches = [];
    
    // Find hashtags
    for (final match in _hashtagRegex.allMatches(text)) {
      matches.add(_MatchInfo(
        start: match.start,
        end: match.end,
        text: match.group(0)!,
        type: _MatchType.hashtag,
      ));
    }
    
    // Find usernames
    for (final match in _usernameRegex.allMatches(text)) {
      matches.add(_MatchInfo(
        start: match.start,
        end: match.end,
        text: match.group(0)!,
        type: _MatchType.username,
      ));
    }
    
    // Sort matches by position
    matches.sort((a, b) => a.start.compareTo(b.start));
    
    // Remove overlapping matches (keep first one)
    final List<_MatchInfo> nonOverlappingMatches = [];
    for (final match in matches) {
      bool overlaps = false;
      for (final existing in nonOverlappingMatches) {
        if (match.start < existing.end && match.end > existing.start) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) {
        nonOverlappingMatches.add(match);
      }
    }
    
    // Re-sort after removing overlaps
    nonOverlappingMatches.sort((a, b) => a.start.compareTo(b.start));
    
    if (nonOverlappingMatches.isEmpty) {
      // No matches found, return simple text
      spans.add(TextSpan(
        text: text,
        style: defaultTextStyle,
      ));
      return spans;
    }

    // Build TextSpans
    int lastIndex = 0;
    for (final match in nonOverlappingMatches) {
      // Add text before match
      if (match.start > lastIndex) {
        final beforeText = text.substring(lastIndex, match.start);
        if (beforeText.isNotEmpty) {
          spans.add(TextSpan(
            text: beforeText,
            style: defaultTextStyle,
          ));
        }
      }
      
      // Add match (hashtag or username)
      if (match.type == _MatchType.hashtag) {
        spans.add(TextSpan(
          text: match.text,
          style: hashtagTextStyle,
          recognizer: onHashtagTap != null
              ? (TapGestureRecognizer()
                ..onTap = () {
                  print('HashtagUtils: Hashtag tapped: ${match.text}');
                  try {
                    onHashtagTap(match.text.substring(1)); // Remove # symbol
                  } catch (e) {
                    print('HashtagUtils: Error in onHashtagTap callback: $e');
                  }
                })
              : null,
        ));
      } else {
        spans.add(TextSpan(
          text: match.text,
          style: usernameTextStyle,
          recognizer: onUsernameTap != null
              ? (TapGestureRecognizer()
                ..onTap = () {
                  print('HashtagUtils: Username tapped: ${match.text}');
                  try {
                    onUsernameTap(match.text.substring(1)); // Remove @ symbol
                  } catch (e) {
                    print('HashtagUtils: Error in onUsernameTap callback: $e');
                  }
                })
              : null,
        ));
      }
      
      lastIndex = match.end;
    }
    
    // Add remaining text after last match
    if (lastIndex < text.length) {
      final remainingText = text.substring(lastIndex);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(
          text: remainingText,
          style: defaultTextStyle,
        ));
      }
    }

    print('HashtagUtils: Created ${spans.length} text spans');
    return spans;
  }

  /// Check if text contains usernames
  static bool hasUsernames(String text) {
    return _usernameRegex.hasMatch(text);
  }
}

enum _MatchType { hashtag, username }

class _MatchInfo {
  final int start;
  final int end;
  final String text;
  final _MatchType type;

  _MatchInfo({
    required this.start,
    required this.end,
    required this.text,
    required this.type,
  });
}
