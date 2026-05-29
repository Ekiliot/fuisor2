import sanitizeHtml from 'sanitize-html';

/**
 * Sanitizes HTML content to prevent XSS attacks
 * Allows only safe HTML tags and attributes
 * 
 * @param {string} html - HTML content to sanitize
 * @returns {string} - Sanitized HTML
 */
export function sanitizeHtmlContent(html) {
  if (!html || typeof html !== 'string') {
    return '';
  }

  return sanitizeHtml(html, {
    allowedTags: [
      'p', 'br', 'strong', 'em', 'u', 'b', 'i',
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'ul', 'ol', 'li',
      'a', 'blockquote', 'img'
    ],
    allowedAttributes: {
      'a': ['href', 'title', 'target'],
      'img': ['src', 'alt', 'width', 'height', 'style']
    },
    allowedSchemes: ['http', 'https', 'mailto', 'data'],
    allowedSchemesByTag: {
      'a': ['http', 'https', 'mailto'],
      'img': ['http', 'https', 'data']
    },
    // Remove dangerous attributes
    allowedStyles: {},
    // Prevent javascript: and data: URLs
    transformTags: {
      'a': (tagName, attribs) => {
        if (attribs.href) {
          // Remove javascript: and data: URLs
          if (attribs.href.toLowerCase().startsWith('javascript:') ||
              attribs.href.toLowerCase().startsWith('data:')) {
            delete attribs.href;
          } else {
            // Ensure external links open in new tab
            attribs.target = '_blank';
            attribs.rel = 'noopener noreferrer';
          }
        }
        return {
          tagName: tagName,
          attribs: attribs
        };
      }
    },
    // Remove all event handlers
    disallowedTagsMode: 'discard',
    // Remove empty tags
    exclusiveFilter: (frame) => {
      // Remove tags with only whitespace
      if (frame.tag && frame.text && frame.text.trim() === '') {
        return false;
      }
      return false;
    }
  });
}

