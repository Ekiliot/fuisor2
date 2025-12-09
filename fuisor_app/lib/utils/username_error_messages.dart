class UsernameErrorMessages {
  // Get random friendly error message for username not found
  static String getRandomNotFoundMessage() {
    final messages = [
      "Error 404: User is in another castle 🏰",
      "Search came up empty. User in stealth mode?",
      "Database says: no such user 🤷",
      "Server shrugged — doesn't know this user",
      "Bummer... This user doesn't exist 😔",
      "Void... This user doesn't exist",
      "We searched everywhere, but... No such user!",
      "Sadly, we don't have this user",
      "Oops! We don't know this user 🙈",
      "This friend isn't with us yet!",
      "This person hasn't joined us yet",
      "User not found",
      "No such user",
      "Username doesn't exist",
      "User is missing",
      "Doesn't exist",
      "This user doesn't exist... Or are they a ninja? 🥷",
      "User not found. Maybe a typo? 🤔",
      "This username is a mystery to us 👻",
      "We searched the whole internet... No such user!",
      "User vanished. Or did they ever exist? 💨",
      "404: User got lost",
      "This user isn't registered. Not yet! ✨",
      "We couldn't find this person. Are you sure about the spelling?",
    ];
    
    // Use current time to get a pseudo-random index
    final index = DateTime.now().millisecond % messages.length;
    return messages[index];
  }
}

