import blessed from 'blessed';
import blessedContrib from 'blessed-contrib';
import { logger } from '../utils/logger.js';
import { spawn, exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';
import { fileURLToPath } from 'url';
import os from 'os';

const execAsync = promisify(exec);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

class ServerManager {
  constructor() {
    this.screen = null;
    this.grid = null;
    this.logBox = null;
    this.statsBox = null;
    this.menuBox = null;
    this.filteredCategory = 'ALL';
    this.serverProcess = null;
    this.isServerRunning = false;
    this.isServerStarting = false;
    this.logs = [];
    this.stats = {};
    this.port = process.env.PORT || 3000;
    this.isWindows = os.platform() === 'win32';
    
    this.init();
  }

  init() {
    // Create screen
    this.screen = blessed.screen({
      smartCSR: true,
      title: 'Fuisor Server Manager'
    });

    // Create grid
    this.grid = new blessedContrib.grid({
      screen: this.screen,
      rows: 12,
      cols: 12
    });

    // Create menu box (left side) - шире, так как там больше элементов
    this.menuBox = this.grid.set(0, 0, 6, 7, blessed.box, {
      tags: true,
      border: {
        type: 'line'
      },
      style: {
        fg: 'white',
        bg: 'black',
        border: {
          fg: '#00ff00'
        }
      }
    });

    // Create stats box (top right) - уже, так как там меньше элементов
    this.statsBox = this.grid.set(0, 7, 6, 5, blessed.box, {
      tags: true,
      border: {
        type: 'line'
      },
      style: {
        fg: 'white',
        bg: 'black',
        border: {
          fg: '#00ff00'
        }
      },
      scrollable: true
    });

    // Create log box (bottom)
    this.logBox = this.grid.set(6, 0, 6, 12, blessed.box, {
      tags: true,
      label: ' ЛОГИ ',
      border: {
        type: 'line'
      },
      style: {
        fg: 'white',
        bg: 'black',
        border: {
          fg: '#00ff00'
        }
      },
      scrollable: true,
      alwaysScroll: true,
      scrollbar: {
        ch: ' ',
        track: {
          bg: 'cyan'
        },
        style: {
          inverse: true
        }
      }
    });

    // Инициализируем контент сразу
    this.updateMenu();
    this.updateStats();
    this.updateLogs();
    this.setupEventListeners();
    this.setupKeyboard();
    
    // Listen to logger events
    logger.on('log', (logEntry) => {
      this.addLog(logEntry);
    });

    // Start server
    this.startServer();

    // Update stats every 2 seconds
    setInterval(() => {
      this.updateStats();
    }, 2000);

    // Render
    this.screen.render();
  }

  setupEventListeners() {
    // Listen for server process events
    if (!this.serverProcess) return;
    
    // Capture stdout but don't duplicate - server already uses logger
    this.serverProcess.stdout.on('data', (data) => {
      const message = data.toString().trim();
      // Only log if it's not already logged by logger (avoid duplicates)
      // Most server logs should come through logger, so we skip console.log output
      if (message && !message.includes('Server is running') && !message.includes('Access from')) {
        logger.server(message);
      }
    });

    this.serverProcess.stderr.on('data', async (data) => {
      const message = data.toString().trim();
      if (message) {
        // Проверяем на ошибку занятого порта
        if (message.includes('EADDRINUSE') || message.includes('address already in use')) {
          logger.serverError('Порт занят, освобождаю...');
          await this.handlePortInUse();
        } else {
          logger.serverError(message);
        }
      }
    });

    this.serverProcess.on('close', (code) => {
      this.isServerRunning = false;
      this.isServerStarting = false;
      if (code !== 0 && code !== null) {
        logger.serverError(`Server process exited with code ${code}`);
      }
      this.updateMenu();
      this.updateStats();
    });
  }

  setupKeyboard() {
    // Quit on Escape, q, or Control-C
    this.screen.key(['escape', 'q', 'C-c'], () => {
      if (this.serverProcess) {
        this.serverProcess.kill();
      }
      return process.exit(0);
    });

    // Filter keys
    this.screen.key(['1'], () => {
      this.filteredCategory = 'ALL';
      this.updateLogs();
      this.updateMenu();
    });

    this.screen.key(['2'], () => {
      this.filteredCategory = 'POSTS';
      this.updateLogs();
      this.updateMenu();
    });

    this.screen.key(['3'], () => {
      this.filteredCategory = 'AUTH';
      this.updateLogs();
      this.updateMenu();
    });

    this.screen.key(['4'], () => {
      this.filteredCategory = 'RECOMMENDATIONS';
      this.updateLogs();
      this.updateMenu();
    });

    this.screen.key(['5'], () => {
      this.filteredCategory = 'SEARCH';
      this.updateLogs();
      this.updateMenu();
    });

    this.screen.key(['6'], () => {
      this.filteredCategory = 'MESSAGES';
      this.updateLogs();
      this.updateMenu();
    });

    this.screen.key(['7'], () => {
      this.filteredCategory = 'ERROR';
      this.updateLogs();
      this.updateMenu();
    });

    this.screen.key(['8'], () => {
      this.filteredCategory = 'USERS';
      this.updateLogs();
      this.updateMenu();
    });

    this.screen.key(['9'], () => {
      this.filteredCategory = 'HASHTAGS';
      this.updateLogs();
      this.updateMenu();
    });

    this.screen.key(['0'], () => {
      this.filteredCategory = 'NOTIFICATIONS';
      this.updateLogs();
      this.updateMenu();
    });

    // Restart server (normal)
    this.screen.key(['r', 'R'], async () => {
      await this.restartServer();
    });

    // Hot restart (Alt+R) - быстрый перезапуск без освобождения порта
    this.screen.key(['M-r', 'M-R'], async () => {
      await this.hotRestart();
    });

    // Stop server
    this.screen.key(['s', 'S'], async () => {
      await this.stopServer();
    });

    // Automatic push to GitHub
    this.screen.key(['p', 'P'], async () => {
      await this.autoPush();
    });

    // Clear logs
    this.screen.key(['c', 'C'], () => {
      logger.clear();
      this.logs = [];
      this.updateLogs();
    });

    // Scroll
    this.screen.key(['up'], () => {
      this.logBox.scroll(-1);
      this.screen.render();
    });

    this.screen.key(['down'], () => {
      this.logBox.scroll(1);
      this.screen.render();
    });
  }

  updateMenu() {
    let serverStatus;
    if (this.isServerStarting) {
      serverStatus = '{yellow-fg}●{/yellow-fg} ЗАПУСКАЕТСЯ';
    } else if (this.isServerRunning) {
      serverStatus = '{green-fg}●{/green-fg} ЗАПУЩЕН';
    } else {
      serverStatus = '{red-fg}●{/red-fg} ОСТАНОВЛЕН';
    }
    
    const filterStatus = this.filteredCategory === 'ALL' ? '{cyan-fg}ВСЕ{/cyan-fg}' : `{yellow-fg}${this.filteredCategory.substring(0, 8)}{/yellow-fg}`;
    
    const menu = `{green-fg}FUISOR MANAGER{/green-fg}
{white-fg}Статус:{/white-fg} ${serverStatus} {white-fg}Порт:{/white-fg} {cyan-fg}${this.port}{/cyan-fg} {white-fg}Фильтр:{/white-fg} ${filterStatus}

{white-fg}ФИЛЬТРЫ{/white-fg}
{yellow-fg}1{/yellow-fg}Все {yellow-fg}2{/yellow-fg}Посты {yellow-fg}3{/yellow-fg}Auth {yellow-fg}4{/yellow-fg}Рек
{yellow-fg}5{/yellow-fg}Поиск {yellow-fg}6{/yellow-fg}Сообщ {yellow-fg}7{/yellow-fg}Ошиб {yellow-fg}8{/yellow-fg}Юзер
{yellow-fg}9{/yellow-fg}Хеш {yellow-fg}0{/yellow-fg}Увед

{white-fg}ДЕЙСТВИЯ{/white-fg}
{yellow-fg}R{/yellow-fg}Перезагр {yellow-fg}Alt+R{/yellow-fg}Hot
{yellow-fg}S{/yellow-fg}Остановить {yellow-fg}P{/yellow-fg}Автопуш
{yellow-fg}C{/yellow-fg}Очистить {yellow-fg}Q{/yellow-fg}Выход`;

    this.menuBox.setContent(menu);
    this.screen.render();
  }

  updateStats() {
    this.stats = logger.getStats();
    const total = Object.values(this.stats).reduce((a, b) => a + b, 0);
    
    const formatStat = (label, value, isError = false) => {
      const color = isError ? 'red-fg' : 'green-fg';
      return `${label}:{${color}}${String(value).padStart(3)}{/${color}}`;
    };
    
    const statsContent = `{green-fg}СТАТИСТИКА{/green-fg} Всего:{cyan-fg}${total}{/cyan-fg}

{yellow-fg}POSTS{/yellow-fg}${formatStat('', this.stats.POSTS || 0)} {yellow-fg}AUTH{/yellow-fg}${formatStat('', this.stats.AUTH || 0)} {yellow-fg}REC{/yellow-fg}${formatStat('', this.stats.RECOMMENDATIONS || 0)} {yellow-fg}SRCH{/yellow-fg}${formatStat('', this.stats.SEARCH || 0)}
{yellow-fg}MSG{/yellow-fg}${formatStat('', this.stats.MESSAGES || 0)} {yellow-fg}USER{/yellow-fg}${formatStat('', this.stats.USERS || 0)} {yellow-fg}FLW{/yellow-fg}${formatStat('', this.stats.FOLLOW || 0)} {yellow-fg}HASH{/yellow-fg}${formatStat('', this.stats.HASHTAGS || 0)}
{yellow-fg}NOT{/yellow-fg}${formatStat('', this.stats.NOTIFICATIONS || 0)} {yellow-fg}SRV{/yellow-fg}${formatStat('', this.stats.SERVER || 0)} {yellow-fg}ERR{/yellow-fg}${formatStat('', this.stats.ERROR || 0, true)} {yellow-fg}GEN{/yellow-fg}${formatStat('', this.stats.GENERAL || 0)}`;

    this.statsBox.setContent(statsContent);
    this.screen.render();
  }

  addLog(logEntry) {
    this.logs.push(logEntry);
    if (this.logs.length > 1000) {
      this.logs.shift();
    }
    this.updateLogs();
  }

  updateLogs() {
    let filteredLogs = this.logs;
    
    if (this.filteredCategory !== 'ALL') {
      if (this.filteredCategory === 'ERROR') {
        filteredLogs = this.logs.filter(log => log.level === 'error');
      } else {
        filteredLogs = this.logs.filter(log => log.category === this.filteredCategory);
      }
    }

    // Get last 50 logs (oldest first, newest at bottom)
    const displayLogs = filteredLogs.slice(-50);
    
    const logContent = displayLogs.map(log => {
      const time = log.timestamp.toLocaleTimeString('ru-RU', { 
        hour: '2-digit', 
        minute: '2-digit', 
        second: '2-digit' 
      });
      const category = this.getCategoryColor(log.category);
      const level = log.level === 'error' ? '{red-fg}ERROR{/red-fg}' : '{green-fg}INFO {/green-fg}';
      
      let line = `{white-fg}[${time}]{/white-fg} ${category} ${level} ${log.message}`;
      
      if (log.data && typeof log.data === 'object' && Object.keys(log.data).length > 0) {
        try {
          const dataStr = JSON.stringify(log.data).substring(0, 80);
          if (dataStr.length > 0) {
            line += ` {gray-fg}${dataStr}...{/gray-fg}`;
          }
        } catch (e) {
          // Skip if can't stringify
        }
      }
      
      return line;
    }).join('\n');

    const finalContent = logContent || '{gray-fg}Нет логов{/gray-fg}';
    this.logBox.setContent(finalContent);
    // Always scroll to bottom to show newest logs
    this.logBox.setScrollPerc(100);
    this.screen.render();
  }

  getCategoryColor(category) {
    const colors = {
      'POSTS': '{cyan-fg}[POSTS]{/cyan-fg}',
      'AUTH': '{yellow-fg}[AUTH]{/yellow-fg}',
      'RECOMMENDATIONS': '{magenta-fg}[REC]{/magenta-fg}',
      'SEARCH': '{blue-fg}[SEARCH]{/blue-fg}',
      'MESSAGES': '{green-fg}[MSG]{/green-fg}',
      'USERS': '{white-fg}[USERS]{/white-fg}',
      'FOLLOW': '{cyan-fg}[FOLLOW]{/cyan-fg}',
      'HASHTAGS': '{yellow-fg}[HASH]{/yellow-fg}',
      'NOTIFICATIONS': '{blue-fg}[NOTIF]{/blue-fg}',
      'SERVER': '{green-fg}[SERVER]{/green-fg}',
      'ERROR': '{red-fg}[ERROR]{/red-fg}',
      'GENERAL': '{gray-fg}[GEN]{/gray-fg}'
    };
    return colors[category] || '{white-fg}[' + category + ']{/white-fg}';
  }

  async killProcessOnPort(port) {
    try {
      if (this.isWindows) {
        // Windows: используем netstat для поиска PID
        try {
          const { stdout } = await execAsync(`netstat -ano | findstr :${port}`);
          const lines = stdout.trim().split('\n').filter(line => line.trim());
          
          if (lines.length === 0) {
            logger.server(`Порт ${port} свободен`);
            return true;
          }
          
          const pids = new Set();
          for (const line of lines) {
            const parts = line.trim().split(/\s+/);
            const pid = parts[parts.length - 1];
            
            if (pid && !isNaN(pid) && pid !== '0') {
              pids.add(pid);
            }
          }
          
          for (const pid of pids) {
            try {
              logger.server(`Освобождение порта ${port}: завершение процесса PID ${pid}`);
              await execAsync(`taskkill /PID ${pid} /F`);
              logger.server(`Процесс ${pid} завершен`);
            } catch (killError) {
              // Процесс уже завершен или нет прав - это нормально
              if (!killError.message.includes('not found') && !killError.message.includes('не найден')) {
                logger.server(`Не удалось завершить процесс ${pid}`);
              }
            }
          }
        } catch (netstatError) {
          // Порт свободен (netstat не нашел процессов)
          logger.server(`Порт ${port} свободен`);
          return true;
        }
      } else {
        // Linux/Mac: используем lsof
        try {
          const { stdout } = await execAsync(`lsof -ti:${port}`);
          const pids = stdout.trim().split('\n').filter(pid => pid && !isNaN(pid));
          
          if (pids.length === 0) {
            logger.server(`Порт ${port} свободен`);
            return true;
          }
          
          for (const pid of pids) {
            try {
              logger.server(`Освобождение порта ${port}: завершение процесса PID ${pid}`);
              await execAsync(`kill -9 ${pid}`);
              logger.server(`Процесс ${pid} завершен`);
            } catch (killError) {
              logger.server(`Не удалось завершить процесс ${pid}`);
            }
          }
        } catch (lsofError) {
          // Порт свободен или lsof не установлен
          if (lsofError.message.includes('No such file') || lsofError.message.includes('command not found')) {
            logger.server(`lsof не установлен, пропускаю проверку порта`);
          } else {
            logger.server(`Порт ${port} свободен`);
          }
          return true;
        }
      }
      
      // Ждем немного, чтобы порт освободился
      await new Promise(resolve => setTimeout(resolve, 1000));
      return true;
    } catch (error) {
      logger.serverError(`Ошибка при освобождении порта: ${error.message}`);
      return false;
    }
  }

  async startServer() {
    if (this.serverProcess) {
      return;
    }

    this.isServerStarting = true;
    this.isServerRunning = false;
    this.updateMenu();
    
    logger.server('Запуск сервера...');
    
    // Проверяем и освобождаем порт перед запуском
    await this.killProcessOnPort(this.port);
    
    const serverPath = path.join(__dirname, '..', 'index.js');
    this.serverProcess = spawn('node', [serverPath], {
      cwd: path.join(__dirname, '..', '..'),
      stdio: ['ignore', 'pipe', 'pipe'],
      shell: true,
      env: { ...process.env, PORT: this.port }
    });

    this.setupEventListeners();
    
    // Ждем немного перед установкой статуса "запущен"
    setTimeout(() => {
      this.isServerStarting = false;
      this.isServerRunning = true;
      this.updateMenu();
      this.updateStats();
      logger.server('Сервер запущен');
    }, 500);
  }

  async handlePortInUse() {
    logger.server('Обнаружен занятый порт, освобождаю...');
    
    // Останавливаем текущий процесс
    if (this.serverProcess) {
      this.serverProcess.kill('SIGTERM');
      this.serverProcess = null;
      this.isServerRunning = false;
      this.isServerStarting = false;
      this.updateMenu();
    }
    
    // Освобождаем порт
    await this.killProcessOnPort(this.port);
    
    // Ждем и перезапускаем
    setTimeout(async () => {
      logger.server('Повторная попытка запуска сервера...');
      await this.startServer();
    }, 1000);
  }

  async hotRestart() {
    logger.server('🔥 Hot restart сервера...');
    
    // Если сервер не запущен, просто запускаем его
    if (!this.serverProcess || !this.isServerRunning) {
      logger.server('Сервер не запущен, запускаю...');
      await this.startServer();
      return;
    }

    // Устанавливаем статус "запускается" сразу
    this.isServerStarting = true;
    this.isServerRunning = false;
    this.updateMenu();

    // Ждем завершения процесса перед запуском нового
    return new Promise((resolve) => {
      if (this.serverProcess) {
        // Удаляем старые обработчики, чтобы избежать конфликтов
        this.serverProcess.removeAllListeners('close');
        
        // Добавляем обработчик завершения
        const onClose = () => {
          this.serverProcess = null;
          
          // Небольшая задержка перед запуском нового процесса
          setTimeout(async () => {
            try {
              const serverPath = path.join(__dirname, '..', 'index.js');
              this.serverProcess = spawn('node', [serverPath], {
                cwd: path.join(__dirname, '..', '..'),
                stdio: ['ignore', 'pipe', 'pipe'],
                shell: true,
                env: { ...process.env, PORT: this.port }
              });

              this.setupEventListeners();
              
              // Ждем немного перед установкой статуса "запущен"
              setTimeout(() => {
                this.isServerStarting = false;
                this.isServerRunning = true;
                this.updateMenu();
                this.updateStats();
                logger.server('🔥 Сервер hot restarted');
                resolve();
              }, 500);
            } catch (error) {
              logger.serverError(`Ошибка при hot restart: ${error.message}`);
              this.isServerStarting = false;
              this.isServerRunning = false;
              this.updateMenu();
              resolve();
            }
          }, 200);
        };

        this.serverProcess.once('close', onClose);
        
        // Отправляем сигнал завершения
        try {
          this.serverProcess.kill('SIGTERM');
        } catch (error) {
          // Процесс уже завершен
          onClose();
        }

        // Таймаут на случай, если процесс не завершится
        setTimeout(() => {
          if (this.serverProcess) {
            try {
              this.serverProcess.kill('SIGKILL');
            } catch (e) {
              // Игнорируем ошибки
            }
            this.serverProcess = null;
            onClose();
          }
        }, 2000);
      } else {
        // Если процесса нет, просто запускаем сервер
        this.startServer().then(resolve);
      }
    });
  }

  async restartServer() {
    logger.server('Перезагрузка сервера...');
    
    if (this.serverProcess) {
      this.serverProcess.kill('SIGTERM');
      this.serverProcess = null;
      this.isServerRunning = false;
      this.isServerStarting = false;
      this.updateMenu();
    }

    // Освобождаем порт перед перезапуском
    await this.killProcessOnPort(this.port);
    
    setTimeout(async () => {
      await this.startServer();
      logger.server('Сервер перезагружен');
    }, 1000);
  }

  async stopServer() {
    if (!this.serverProcess && !this.isServerRunning) {
      logger.server('Сервер уже остановлен');
      return;
    }

    logger.server('Остановка сервера...');
    
    if (this.serverProcess) {
      try {
        this.serverProcess.kill('SIGTERM');
        
        // Ждем завершения процесса
        await new Promise((resolve) => {
          if (this.serverProcess) {
            const timeout = setTimeout(() => {
              // Если процесс не завершился, принудительно убиваем
              if (this.serverProcess) {
                try {
                  this.serverProcess.kill('SIGKILL');
                } catch (e) {
                  // Игнорируем ошибки
                }
              }
              resolve();
            }, 3000);

            this.serverProcess.once('close', () => {
              clearTimeout(timeout);
              resolve();
            });
          } else {
            resolve();
          }
        });
      } catch (error) {
        logger.serverError(`Ошибка при остановке сервера: ${error.message}`);
      }
      
      this.serverProcess = null;
    }

    this.isServerRunning = false;
    this.isServerStarting = false;
    this.updateMenu();
    this.updateStats();
    logger.server('Сервер остановлен');
  }

  async autoPush() {
    logger.server('🚀 Запуск автоматического пуша в GitHub (ekiliot/fuisor2)...');
    
    try {
      const autoPushPath = path.join(__dirname, 'auto-push.js');
      const rootDir = path.join(__dirname, '..', '..');
      
      // Запускаем скрипт автоматического пуша
      const pushProcess = spawn('node', [autoPushPath], {
        cwd: rootDir,
        stdio: ['ignore', 'pipe', 'pipe'],
        shell: true
      });

      // Логируем вывод скрипта
      pushProcess.stdout.on('data', (data) => {
        const message = data.toString().trim();
        if (message) {
          logger.server(`[AUTO-PUSH] ${message}`);
        }
      });

      pushProcess.stderr.on('data', (data) => {
        const message = data.toString().trim();
        if (message) {
          logger.serverError(`[AUTO-PUSH] ${message}`);
        }
      });

      pushProcess.on('close', (code) => {
        if (code === 0) {
          logger.server('✅ Автоматический пуш успешно завершен');
        } else {
          logger.serverError(`❌ Автоматический пуш завершился с кодом ${code}`);
        }
      });

      pushProcess.on('error', (error) => {
        logger.serverError(`Ошибка при запуске автоматического пуша: ${error.message}`);
      });
    } catch (error) {
      logger.serverError(`Ошибка при выполнении автоматического пуша: ${error.message}`);
    }
  }
}

// Start manager if run directly
const isMainModule = process.argv[1] && process.argv[1].endsWith('server-manager.js');

if (isMainModule) {
  new ServerManager();
}

export default ServerManager;

