import express from 'express';
import multer from 'multer';
import { supabaseAdmin } from '../config/supabase.js';
import { validateAuth } from '../middleware/auth.middleware.js';
import { validateChatId, validateMessageId } from '../middleware/validation.middleware.js';

const router = express.Router();

// Multer setup for file uploads (voice messages, images, etc.)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 20 * 1024 * 1024, // 20MB max
  },
});

// ==============================================
// Helper функция: Проверка участия в чате
// ==============================================
async function checkChatParticipant(chatId, userId) {
  const { data: participant, error } = await supabaseAdmin
    .from('chat_participants')
    .select('chat_id')
    .eq('chat_id', chatId)
    .eq('user_id', userId)
    .single();

  if (error || !participant) {
    return false;
  }
  return true;
}

// ==============================================
// 1. GET /api/messages/chats
// Получить все чаты текущего пользователя
// ==============================================
router.get('/chats', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;

    // Получаем все чаты где пользователь является участником
    // По умолчанию исключаем архивированные (можно добавить параметр includeArchived)
    const includeArchived = req.query.includeArchived === 'true';
    
    let participantQuery = supabaseAdmin
      .from('chat_participants')
      .select('chat_id, unread_count, is_archived, is_pinned')
      .eq('user_id', userId);
    
    if (!includeArchived) {
      // Исключаем архивированные чаты (is_archived = false или null)
      participantQuery = participantQuery.or('is_archived.is.null,is_archived.eq.false');
    }
    
    const { data: participantRecords, error: participantError } = await participantQuery;

    if (participantError) {
      console.error('Error fetching participant records:', participantError);
      return res.status(500).json({ error: participantError.message });
    }

    const chatIds = participantRecords?.map(p => p.chat_id) || [];

    if (chatIds.length === 0) {
      return res.json({ chats: [] });
    }

    // Получаем чаты с участниками и последним сообщением
    const { data: chats, error: chatsError } = await supabaseAdmin
      .from('chats')
      .select(`
        id,
        type,
        created_at,
        updated_at,
        participants:chat_participants(
          user_id,
          unread_count,
          last_read_at,
          is_archived,
          is_pinned,
          user:profiles!user_id(
            id,
            username,
            name,
            avatar_url
          )
        )
      `)
      .in('id', chatIds)
      .order('updated_at', { ascending: false });

    if (chatsError) {
      console.error('Error fetching chats:', chatsError);
      return res.status(500).json({ error: chatsError.message });
    }

    // Получаем последнее сообщение для каждого чата
    const chatsWithMessages = await Promise.all(
      chats.map(async (chat) => {
        const { data: lastMessage, error: lastMessageError } = await supabaseAdmin
          .from('messages')
          .select(`
            id,
            chat_id,
            content,
            sender_id,
            is_read,
            created_at,
            updated_at,
            sender:profiles!sender_id(
              id,
              username,
              name,
              avatar_url
            )
          `)
          .eq('chat_id', chat.id)
          .is('deleted_at', null) // Только неудаленные сообщения
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle(); // Используем maybeSingle вместо single для обработки отсутствия сообщений

        if (lastMessageError) {
          console.error('Error fetching last message for chat', chat.id, ':', lastMessageError);
        }

        const myParticipant = chat.participants.find(p => p.user_id === userId);

        if (chat.type === 'direct') {
          const otherParticipant = chat.participants.find(p => p.user_id !== userId);
          
          // Форматируем lastMessage для правильной структуры
          let formattedLastMessage = null;
          if (lastMessage) {
            formattedLastMessage = {
              id: lastMessage.id,
              chat_id: lastMessage.chat_id || chat.id,
              sender_id: lastMessage.sender_id,
              content: lastMessage.content,
              is_read: lastMessage.is_read || false,
              created_at: lastMessage.created_at,
              updated_at: lastMessage.updated_at || lastMessage.created_at,
              sender: lastMessage.sender || null,
            };
          }
          
          return {
            id: chat.id,
            type: chat.type || 'direct',
            created_at: chat.created_at,
            updated_at: chat.updated_at || chat.created_at,
            otherUser: otherParticipant?.user || null,
          unreadCount: myParticipant?.unread_count ?? 0,
          isArchived: myParticipant?.is_archived ?? false,
          isPinned: myParticipant?.is_pinned ?? false,
          lastMessage: formattedLastMessage,
        };
      }

        // Форматируем lastMessage для правильной структуры
        let formattedLastMessage = null;
        if (lastMessage) {
          formattedLastMessage = {
            id: lastMessage.id,
            chat_id: lastMessage.chat_id || chat.id,
            sender_id: lastMessage.sender_id,
            content: lastMessage.content,
            is_read: lastMessage.is_read || false,
            created_at: lastMessage.created_at,
            updated_at: lastMessage.updated_at || lastMessage.created_at,
            sender: lastMessage.sender || null,
          };
        }

        return {
          id: chat.id,
          type: chat.type || 'group',
          created_at: chat.created_at,
          updated_at: chat.updated_at || chat.created_at,
          participants: (chat.participants || []).map(p => ({
            user: p.user,
            unreadCount: p.unread_count ?? 0,
            lastReadAt: p.last_read_at || null,
          })),
          unreadCount: myParticipant?.unread_count ?? 0,
          isArchived: myParticipant?.is_archived ?? false,
          isPinned: myParticipant?.is_pinned ?? false,
          lastMessage: formattedLastMessage,
        };
      })
    );

    res.json({ chats: chatsWithMessages });
  } catch (error) {
    console.error('Error in GET /api/messages/chats:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// 2. POST /api/messages/chats
// Создать новый прямой чат
// ==============================================
router.post('/chats', validateAuth, async (req, res) => {
  try {
    const { otherUserId } = req.body;
    const currentUserId = req.user.id;

    if (!otherUserId) {
      return res.status(400).json({ error: 'otherUserId is required' });
    }

    // Нельзя создать чат с собой
    if (otherUserId === currentUserId) {
      return res.status(400).json({ error: 'Cannot create chat with yourself' });
    }

    // Проверка существующего прямого чата
    const { data: currentUserChats, error: currentUserError } = await supabaseAdmin
      .from('chat_participants')
      .select('chat_id')
      .eq('user_id', currentUserId);

    if (currentUserError) {
      return res.status(500).json({ error: currentUserError.message });
    }

    const { data: otherUserChats, error: otherUserError } = await supabaseAdmin
      .from('chat_participants')
      .select('chat_id')
      .eq('user_id', otherUserId);

    if (otherUserError) {
      return res.status(500).json({ error: otherUserError.message });
    }

    const currentUserChatIds = currentUserChats?.map(c => c.chat_id) || [];
    const otherUserChatIds = otherUserChats?.map(c => c.chat_id) || [];

    // Находим пересечение - чаты где оба пользователя участники
    const commonChatIds = currentUserChatIds.filter(id => otherUserChatIds.includes(id));

    if (commonChatIds.length > 0) {
      // Проверяем что это direct чат
      const { data: existingDirectChat, error: chatCheckError } = await supabaseAdmin
        .from('chats')
        .select('id, type, created_at, updated_at')
        .eq('id', commonChatIds[0])
        .eq('type', 'direct')
        .single();

      if (!chatCheckError && existingDirectChat) {
        // Чат уже существует, возвращаем его с участниками
        const { data: participants, error: participantsError } = await supabaseAdmin
          .from('chat_participants')
          .select(`
            user_id,
            unread_count,
            user:profiles!user_id(id, username, name, avatar_url)
          `)
          .eq('chat_id', existingDirectChat.id);

        if (participantsError) {
          console.error('Error fetching participants:', participantsError);
          return res.status(500).json({ error: participantsError.message });
        }

        const otherParticipant = participants?.find(p => p.user_id !== currentUserId);
        const myParticipant = participants?.find(p => p.user_id === currentUserId);

        return res.status(200).json({
          chat: {
            id: existingDirectChat.id,
            type: existingDirectChat.type,
            created_at: existingDirectChat.created_at,
            updated_at: existingDirectChat.updated_at,
            otherUser: otherParticipant?.user || null,
            unreadCount: myParticipant?.unread_count || 0,
          },
        });
      }
    }

    // Создаем новый чат
    const { data: newChat, error: createError } = await supabaseAdmin
      .from('chats')
      .insert([{ type: 'direct' }])
      .select()
      .single();

    if (createError) {
      console.error('Error creating chat:', createError);
      return res.status(500).json({ error: createError.message });
    }

    // Добавляем участников
    const { data: participants, error: participantsError } = await supabaseAdmin
      .from('chat_participants')
      .insert([
        { chat_id: newChat.id, user_id: currentUserId },
        { chat_id: newChat.id, user_id: otherUserId },
      ])
      .select(`
        user_id,
        unread_count,
        user:profiles!user_id(id, username, name, avatar_url)
      `);

    if (participantsError) {
      console.error('Error adding participants:', participantsError);
      return res.status(500).json({ error: participantsError.message });
    }

    const otherParticipant = participants?.find(p => p.user_id !== currentUserId);

    res.status(201).json({
      chat: {
        ...newChat,
        otherUser: otherParticipant?.user || null,
        unreadCount: 0,
      },
    });
  } catch (error) {
    console.error('Error in POST /api/messages/chats:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// 3. GET /api/messages/chats/:chatId
// Получить конкретный чат
// ==============================================
router.get('/chats/:chatId', validateAuth, validateChatId, async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const userId = req.user.id;

    // Проверка участия (с timing attack protection)
    const isParticipant = await checkChatParticipant(chatId, userId);
    
    if (!isParticipant) {
      // Защита от timing attacks: случайная задержка
      await new Promise(r => setTimeout(r, Math.random() * 100));
      return res.status(404).json({ error: 'Chat not found' });
    }

    // Получаем чат с участниками
    const { data: chat, error: chatError } = await supabaseAdmin
      .from('chats')
      .select(`
        id,
        type,
        created_at,
        updated_at,
        participants:chat_participants(
          user_id,
          unread_count,
          last_read_at,
          user:profiles!user_id(id, username, name, avatar_url)
        )
      `)
      .eq('id', chatId)
      .single();

    if (chatError) {
      return res.status(404).json({ error: 'Chat not found' });
    }

    const myParticipant = chat.participants.find(p => p.user_id === userId);

    if (chat.type === 'direct') {
      const otherParticipant = chat.participants.find(p => p.user_id !== userId);
      return res.json({
        chat: {
          id: chat.id,
          type: chat.type,
          created_at: chat.created_at,
          updated_at: chat.updated_at,
          otherUser: otherParticipant?.user || null,
          unreadCount: myParticipant?.unread_count || 0,
        },
      });
    }

    res.json({
      chat: {
        id: chat.id,
        type: chat.type,
        created_at: chat.created_at,
        updated_at: chat.updated_at,
        participants: chat.participants.map(p => ({
          user: p.user,
          unreadCount: p.unread_count,
          lastReadAt: p.last_read_at,
        })),
        unreadCount: myParticipant?.unread_count || 0,
      },
    });
  } catch (error) {
    console.error('Error in GET /api/messages/chats/:chatId:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// 4. GET /api/messages/chats/:chatId/messages
// Получить сообщения чата
// ==============================================
router.get('/chats/:chatId/messages', validateAuth, validateChatId, async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const userId = req.user.id;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 50;
    const offset = (page - 1) * limit;

    // Проверка участия
    const isParticipant = await checkChatParticipant(chatId, userId);
    
    if (!isParticipant) {
      await new Promise(r => setTimeout(r, Math.random() * 100));
      return res.status(404).json({ error: 'Chat not found' });
    }

    console.log('GET /chats/:chatId/messages - Request:', {
      chatId,
      userId,
      page,
      limit,
      offset,
    });

    // Получаем сообщения (RLS автоматически фильтрует по участию и soft delete)
    const { data: messages, error: messagesError } = await supabaseAdmin
      .from('messages')
      .select(`
        id,
        chat_id,
        sender_id,
        content,
        message_type,
        media_url,
        thumbnail_url,
        post_id,
        media_duration,
        media_size,
        is_read,
        read_at,
        created_at,
        updated_at,
        sender:profiles!sender_id(
          id,
          username,
          name,
          avatar_url
        )
      `)
      .eq('chat_id', chatId)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (messagesError) {
      console.error('Error fetching messages:', messagesError);
      return res.status(500).json({ error: messagesError.message });
    }

    console.log('GET /chats/:chatId/messages - Response:', {
      messagesCount: messages?.length || 0,
      hasMessages: !!messages && messages.length > 0,
    });

    // Возвращаем пустой массив если сообщений нет (для нового чата это нормально)
    res.json({
      messages: messages && messages.length > 0 ? messages.reverse() : [], // Возвращаем в хронологическом порядке (старые -> новые)
      page,
      limit,
    });
  } catch (error) {
    console.error('Error in GET /api/messages/chats/:chatId/messages:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// 5. POST /api/messages/chats/:chatId/upload
// Загрузить медиа файл (voice, image, video)
// ==============================================
router.post('/chats/:chatId/upload', validateAuth, validateChatId, upload.single('file'), async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const userId = req.user.id;
    const file = req.file;
    const { messageType, duration } = req.body;

    if (!file) {
      return res.status(400).json({ error: 'No file provided' });
    }

    if (!['voice', 'image', 'video', 'file'].includes(messageType)) {
      return res.status(400).json({ error: 'Invalid message type' });
    }

    const isParticipant = await checkChatParticipant(chatId, userId);
    if (!isParticipant) {
      await new Promise(r => setTimeout(r, Math.random() * 100));
      return res.status(404).json({ error: 'Chat not found' });
    }

    const fileExt = file.originalname.split('.').pop();
    const fileName = `${userId}/${chatId}/${Date.now()}.${fileExt}`;

    const { data: uploadData, error: uploadError } = await supabaseAdmin
      .storage
      .from('dm_media')
      .upload(fileName, file.buffer, {
        contentType: file.mimetype,
        upsert: false,
      });

    if (uploadError) {
      console.error('Upload error:', uploadError);
      return res.status(500).json({ error: 'Failed to upload file' });
    }

    res.status(200).json({
      mediaUrl: fileName,
      messageType,
      mediaSize: file.size,
      mediaDuration: duration ? parseInt(duration) : null,
    });
  } catch (error) {
    console.error('Error in POST /chats/:chatId/upload:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// 6. POST /api/messages/chats/:chatId/messages
// Отправить сообщение (текст или медиа)
// ==============================================
router.post('/chats/:chatId/messages', validateAuth, validateChatId, async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const userId = req.user.id;
    const { content, messageType, mediaUrl, thumbnailUrl, postId, mediaDuration, mediaSize } = req.body;

    console.log('POST /chats/:chatId/messages - Request:', {
      chatId,
      userId,
      hasContent: !!content,
      messageType: messageType || 'text',
      hasMedia: !!mediaUrl,
    });

    if (messageType === 'text' && (!content || content.trim().length === 0)) {
      return res.status(400).json({ error: 'Message content is required' });
    }

    if (messageType !== 'text' && !mediaUrl) {
      return res.status(400).json({ error: 'Media URL is required for media messages' });
    }

    if (content && content.length > 5000) {
      return res.status(400).json({ error: 'Message content is too long (max 5000 characters)' });
    }

    // Проверка участия
    const isParticipant = await checkChatParticipant(chatId, userId);
    
    console.log('POST /chats/:chatId/messages - Participant check:', {
      chatId,
      userId,
      isParticipant,
    });
    
    if (!isParticipant) {
      await new Promise(r => setTimeout(r, Math.random() * 100));
      return res.status(404).json({ error: 'Chat not found' });
    }

    // Создаем сообщение
    const messageData = {
      chat_id: chatId,
      sender_id: userId,
      content: content?.trim() || null,
      message_type: messageType || 'text',
      media_url: mediaUrl || null,
      thumbnail_url: thumbnailUrl || null,
      post_id: postId || null,
      media_duration: typeof mediaDuration === 'number' ? mediaDuration : null,
      media_size: typeof mediaSize === 'number' ? mediaSize : null,
    };
    
    console.log('POST /chats/:chatId/messages - Message data:', messageData);

    const { data: message, error: messageError} = await supabaseAdmin
      .from('messages')
      .insert(messageData)
      .select(`
        id,
        chat_id,
        sender_id,
        content,
        message_type,
        media_url,
        thumbnail_url,
        post_id,
        media_duration,
        media_size,
        is_read,
        created_at,
        updated_at,
        sender:profiles!sender_id(
          id,
          username,
          name,
          avatar_url
        )
      `)
      .single();

    if (messageError) {
      console.error('Error creating message:', messageError);
      return res.status(500).json({ error: messageError.message });
    }

    console.log('POST /chats/:chatId/messages - Created message:', {
      id: message.id,
      message_type: message.message_type,
      media_url: message.media_url,
      hasContent: !!message.content,
    });

    // Триггеры автоматически:
    // - Обновят chats.updated_at
    // - Увеличат unread_count для получателей

    res.status(201).json({ message });
  } catch (error) {
    console.error('Error in POST /api/messages/chats/:chatId/messages:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// 6. PUT /api/messages/chats/:chatId/messages/:messageId/read
// Отметить сообщение как прочитанное
// ==============================================
router.put('/chats/:chatId/messages/:messageId/read', validateAuth, validateChatId, validateMessageId, async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const messageId = req.params.messageId;
    const userId = req.user.id;

    // Проверка участия
    const isParticipant = await checkChatParticipant(chatId, userId);
    
    if (!isParticipant) {
      await new Promise(r => setTimeout(r, Math.random() * 100));
      return res.status(404).json({ error: 'Chat not found' });
    }

    // Проверяем что сообщение существует и принадлежит этому чату
    const { data: message, error: messageError } = await supabaseAdmin
      .from('messages')
      .select('id, chat_id, sender_id, created_at')
      .eq('id', messageId)
      .eq('chat_id', chatId)
      .is('deleted_at', null)
      .single();

    if (messageError || !message) {
      return res.status(404).json({ error: 'Message not found' });
    }

    console.log('PUT /chats/:chatId/messages/:messageId/read - Request:', {
      chatId,
      messageId,
      userId,
      messageSenderId: message.sender_id,
    });

    const now = new Date().toISOString();
    
    // Помечаем все сообщения до этого момента (и само сообщение) как прочитанные
    // Только для сообщений, где текущий пользователь - получатель (не отправитель)
    console.log('Attempting to mark messages as read:', {
      chatId,
      userId,
      senderIdToExclude: userId,
      upToCreatedAt: message.created_at,
    });
    
    const { data: markedMessages, error: markReadError } = await supabaseAdmin
      .from('messages')
      .update({
        is_read: true,
        read_at: now,
      })
      .eq('chat_id', chatId)
      .neq('sender_id', userId) // Только чужие сообщения
      .lte('created_at', message.created_at) // До этого сообщения включительно
      .is('deleted_at', null) // Только неудаленные сообщения
      .select('id, sender_id, is_read, read_at');

    if (markReadError) {
      console.error('Error marking messages as read:', markReadError);
      // Не возвращаем ошибку, продолжаем обновление last_read_at
    } else {
      console.log(`Successfully marked ${markedMessages?.length || 0} messages as read in chat ${chatId}`);
      if (markedMessages && markedMessages.length > 0) {
        console.log('Sample marked message:', {
          id: markedMessages[0].id,
          sender_id: markedMessages[0].sender_id,
          is_read: markedMessages[0].is_read,
          read_at: markedMessages[0].read_at,
        });
      }
    }

    // Обновляем last_read_at для участника (триггер сбросит unread_count)
    const { data: participant, error: participantError } = await supabaseAdmin
      .from('chat_participants')
      .update({
        last_read_at: now,
      })
      .eq('chat_id', chatId)
      .eq('user_id', userId)
      .select()
      .single();

    if (participantError) {
      console.error('Error updating last_read_at:', participantError);
      return res.status(500).json({ error: participantError.message });
    }

    res.json({ message: 'Message marked as read', unreadCount: participant.unread_count });
  } catch (error) {
    console.error('Error in PUT /api/messages/chats/:chatId/messages/:messageId/read:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// 7. DELETE /api/messages/chats/:chatId/messages/:messageId
// Удалить сообщение (soft delete)
// ==============================================
router.delete('/chats/:chatId/messages/:messageId', validateAuth, validateChatId, validateMessageId, async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const messageId = req.params.messageId;
    const userId = req.user.id;

    // Проверка участия
    const isParticipant = await checkChatParticipant(chatId, userId);
    
    if (!isParticipant) {
      await new Promise(r => setTimeout(r, Math.random() * 100));
      return res.status(404).json({ error: 'Chat not found' });
    }

    // Проверяем что сообщение принадлежит отправителю
    const { data: message, error: messageError } = await supabaseAdmin
      .from('messages')
      .select('id, sender_id, deleted_by_ids')
      .eq('id', messageId)
      .eq('chat_id', chatId)
      .single();

    if (messageError || !message) {
      return res.status(404).json({ error: 'Message not found' });
    }

    if (message.sender_id !== userId) {
      return res.status(403).json({ error: 'Unauthorized: Cannot delete another user\'s message' });
    }

    // Soft delete: добавляем пользователя в deleted_by_ids или устанавливаем deleted_at
    const deletedByIds = Array.isArray(message.deleted_by_ids) 
      ? [...message.deleted_by_ids, userId]
      : [userId];

    const { data: updatedMessage, error: updateError } = await supabaseAdmin
      .from('messages')
      .update({
        deleted_at: new Date().toISOString(),
        deleted_by_ids: deletedByIds,
      })
      .eq('id', messageId)
      .select()
      .single();

    if (updateError) {
      console.error('Error deleting message:', updateError);
      return res.status(500).json({ error: updateError.message });
    }

    res.json({ message: 'Message deleted successfully', deleted: true });
  } catch (error) {
    console.error('Error in DELETE /api/messages/chats/:chatId/messages/:messageId:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// 8. GET /api/messages/chats/:chatId/media/signed-url?path=...
// Получить signed URL для приватного медиа файла
// ==============================================
router.get('/chats/:chatId/media/signed-url', validateAuth, validateChatId, async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const userId = req.user.id;
    // Получаем путь к файлу из query параметра
    const mediaPath = req.query.path;
    
    console.log('GET /chats/:chatId/media/signed-url - Request:', {
      chatId,
      userId,
      mediaPath,
    });

    if (!mediaPath) {
      return res.status(400).json({ error: 'Media path is required' });
    }

    // Проверка участия в чате
    const isParticipant = await checkChatParticipant(chatId, userId);
    if (!isParticipant) {
      await new Promise(r => setTimeout(r, Math.random() * 100));
      return res.status(404).json({ error: 'Chat not found' });
    }

    // Проверяем, что путь к файлу соответствует структуре userId/chatId/...
    const pathParts = mediaPath.split('/');
    if (pathParts.length < 3) {
      return res.status(400).json({ error: 'Invalid media path format' });
    }

    // Проверяем, что chatId в пути соответствует запрошенному chatId
    if (pathParts[1] !== chatId) {
      return res.status(403).json({ error: 'Media path does not match chat ID' });
    }

    // Создаем signed URL (действителен 1 час = 3600 секунд)
    const { data, error } = await supabaseAdmin.storage
      .from('dm_media')
      .createSignedUrl(mediaPath, 3600);

    if (error) {
      console.error('Error creating signed URL:', error);
      return res.status(500).json({ error: 'Failed to create signed URL' });
    }

    console.log('GET /chats/:chatId/media/signed-url - Success:', {
      mediaPath,
      hasSignedUrl: !!data?.signedUrl,
    });

    res.json({ signedUrl: data.signedUrl });
  } catch (error) {
    console.error('Error in GET /api/messages/chats/:chatId/media/signed-url:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// PUT /api/messages/chats/:chatId/pin
// Закрепить/открепить чат
// ==============================================
router.put('/chats/:chatId/pin', validateAuth, validateChatId, async (req, res) => {
  try {
    const { chatId } = req.params;
    const userId = req.user.id;
    const { isPinned } = req.body;

    if (typeof isPinned !== 'boolean') {
      return res.status(400).json({ error: 'isPinned must be a boolean' });
    }

    // Проверяем участие в чате
    const isParticipant = await checkChatParticipant(chatId, userId);
    if (!isParticipant) {
      return res.status(403).json({ error: 'You are not a participant of this chat' });
    }

    // Обновляем is_pinned для текущего пользователя
    const { data, error } = await supabaseAdmin
      .from('chat_participants')
      .update({ is_pinned: isPinned })
      .eq('chat_id', chatId)
      .eq('user_id', userId)
      .select()
      .single();

    if (error) {
      console.error('Error updating chat pin status:', error);
      return res.status(500).json({ error: error.message });
    }

    res.json({ isPinned: data.is_pinned });
  } catch (error) {
    console.error('Error in pin chat endpoint:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// PUT /api/messages/chats/:chatId/archive
// Архивировать/разархивировать чат
// ==============================================
router.put('/chats/:chatId/archive', validateAuth, validateChatId, async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const userId = req.user.id;
    const { isArchived } = req.body;

    // Проверка участия в чате
    const isParticipant = await checkChatParticipant(chatId, userId);
    if (!isParticipant) {
      await new Promise(r => setTimeout(r, Math.random() * 100));
      return res.status(404).json({ error: 'Chat not found' });
    }

    // Обновляем статус архивирования для текущего пользователя
    const { data: updatedParticipant, error: updateError } = await supabaseAdmin
      .from('chat_participants')
      .update({ is_archived: isArchived === true })
      .eq('chat_id', chatId)
      .eq('user_id', userId)
      .select()
      .single();

    if (updateError) {
      console.error('Error updating archive status:', updateError);
      return res.status(500).json({ error: updateError.message });
    }

    console.log('PUT /chats/:chatId/archive - Success:', {
      chatId,
      userId,
      isArchived,
    });

    res.json({ 
      success: true,
      isArchived: updatedParticipant.is_archived 
    });
  } catch (error) {
    console.error('Error in PUT /api/messages/chats/:chatId/archive:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

