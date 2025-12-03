/**
 * Extract usernames from text that start with @
 * @param {string} text - Text to extract mentions from
 * @returns {Array<string>} - Array of usernames (without @)
 */
export function extractMentions(text) {
  if (!text || typeof text !== 'string') {
    return [];
  }

  // Match @username pattern (supports Cyrillic, Latin, numbers, underscores)
  // Remove @ symbol and return just the username
  const mentionRegex = /@([а-яёА-ЯЁa-zA-Z0-9_]+)/g;
  const mentions = [];
  let match;

  while ((match = mentionRegex.exec(text)) !== null) {
    const username = match[1];
    // Avoid duplicates
    if (!mentions.includes(username)) {
      mentions.push(username);
    }
  }

  return mentions;
}

