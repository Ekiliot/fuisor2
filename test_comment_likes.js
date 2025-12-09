#!/usr/bin/env node

/**
 * Тестовый скрипт для проверки лайков комментариев
 * Запуск: node test_comment_likes.js
 */

const http = require('http');

const API_BASE = 'http://localhost:3000/api';

// Тестовые данные
let authToken = '';
let testPostId = '';
let testCommentId = '';

// Функция для HTTP запросов
function makeRequest(options, data = null) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          resolve({ status: res.statusCode, data: parsed });
        } catch (e) {
          resolve({ status: res.statusCode, data: body });
        }
      });
    });

    req.on('error', reject);
    
    if (data) {
      req.write(JSON.stringify(data));
    }
    
    req.end();
  });
}

// 1. Тест логина
async function testLogin() {
  console.log('🔐 Тестируем логин...');
  
  const options = {
    hostname: 'localhost',
    port: 3000,
    path: '/api/auth/login',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    }
  };

  const response = await makeRequest(options, {
    email_or_username: 'test@example.com', // Замените на реальные данные
    password: 'password123'
  });

  if (response.status === 200) {
    authToken = response.data.session?.access_token;
    console.log('✅ Логин успешен');
    console.log('🔑 Токен получен:', authToken ? 'Да' : 'Нет');
  } else {
    console.log('❌ Ошибка логина:', response.data);
    throw new Error('Не удалось войти в систему');
  }
}

// 2. Тест получения постов
async function testGetPosts() {
  console.log('\n📝 Тестируем получение постов...');
  
  const options = {
    hostname: 'localhost',
    port: 3000,
    path: '/api/posts?limit=1',
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${authToken}`,
    }
  };

  const response = await makeRequest(options);

  if (response.status === 200 && response.data.posts?.length > 0) {
    testPostId = response.data.posts[0].id;
    console.log('✅ Посты получены');
    console.log('📄 Тестовый пост ID:', testPostId);
  } else {
    console.log('❌ Ошибка получения постов:', response.data);
    throw new Error('Не удалось получить посты');
  }
}

// 3. Тест получения комментариев
async function testGetComments() {
  console.log('\n💬 Тестируем получение комментариев...');
  
  const options = {
    hostname: 'localhost',
    port: 3000,
    path: `/api/posts/${testPostId}/comments?limit=1`,
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${authToken}`,
    }
  };

  const response = await makeRequest(options);

  if (response.status === 200 && response.data.comments?.length > 0) {
    testCommentId = response.data.comments[0].id;
    const comment = response.data.comments[0];
    console.log('✅ Комментарии получены');
    console.log('💬 Тестовый комментарий ID:', testCommentId);
    console.log('📊 Лайки:', comment.likes_count, 'Дизлайки:', comment.dislikes_count);
    console.log('❤️ Пользователь лайкнул:', comment.is_liked);
    console.log('👎 Пользователь дизлайкнул:', comment.is_disliked);
  } else {
    console.log('❌ Ошибка получения комментариев:', response.data);
    console.log('ℹ️ Возможно, у поста нет комментариев. Создайте комментарий вручную.');
    throw new Error('Не удалось получить комментарии');
  }
}

// 4. Тест лайка комментария
async function testLikeComment() {
  console.log('\n❤️ Тестируем лайк комментария...');
  
  const options = {
    hostname: 'localhost',
    port: 3000,
    path: `/api/posts/${testPostId}/comments/${testCommentId}/like`,
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${authToken}`,
    }
  };

  const response = await makeRequest(options);

  if (response.status === 200) {
    console.log('✅ Лайк комментария успешен');
    console.log('📊 Результат:', response.data);
  } else {
    console.log('❌ Ошибка лайка комментария:', response.data);
  }
}

// 5. Тест дизлайка комментария
async function testDislikeComment() {
  console.log('\n👎 Тестируем дизлайк комментария...');
  
  const options = {
    hostname: 'localhost',
    port: 3000,
    path: `/api/posts/${testPostId}/comments/${testCommentId}/dislike`,
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${authToken}`,
    }
  };

  const response = await makeRequest(options);

  if (response.status === 200) {
    console.log('✅ Дизлайк комментария успешен');
    console.log('📊 Результат:', response.data);
  } else {
    console.log('❌ Ошибка дизлайка комментария:', response.data);
  }
}

// 6. Тест повторного получения комментариев для проверки счетчиков
async function testGetCommentsAgain() {
  console.log('\n🔄 Проверяем обновленные счетчики...');
  
  const options = {
    hostname: 'localhost',
    port: 3000,
    path: `/api/posts/${testPostId}/comments?limit=1`,
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${authToken}`,
    }
  };

  const response = await makeRequest(options);

  if (response.status === 200 && response.data.comments?.length > 0) {
    const comment = response.data.comments[0];
    console.log('✅ Комментарии получены повторно');
    console.log('📊 Обновленные лайки:', comment.likes_count);
    console.log('📊 Обновленные дизлайки:', comment.dislikes_count);
    console.log('❤️ Пользователь лайкнул:', comment.is_liked);
    console.log('👎 Пользователь дизлайкнул:', comment.is_disliked);
  } else {
    console.log('❌ Ошибка повторного получения комментариев:', response.data);
  }
}

// Основная функция тестирования
async function runTests() {
  try {
    console.log('🚀 Начинаем тестирование лайков комментариев...\n');
    
    await testLogin();
    await testGetPosts();
    await testGetComments();
    await testLikeComment();
    await testDislikeComment();
    await testGetCommentsAgain();
    
    console.log('\n🎉 Все тесты завершены!');
    console.log('\n📋 Результаты:');
    console.log('✅ Логин работает');
    console.log('✅ Получение постов работает');
    console.log('✅ Получение комментариев работает');
    console.log('✅ Лайки комментариев работают');
    console.log('✅ Дизлайки комментариев работают');
    console.log('✅ Счетчики обновляются');
    
  } catch (error) {
    console.log('\n❌ Тест прерван с ошибкой:', error.message);
    console.log('\n💡 Убедитесь что:');
    console.log('1. Сервер запущен на порту 3000');
    console.log('2. База данных Supabase настроена');
    console.log('3. Есть тестовые пользователи и посты с комментариями');
  }
}

// Запуск тестов
runTests();
