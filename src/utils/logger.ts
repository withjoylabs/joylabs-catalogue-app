import * as FileSystem from 'expo-file-system';
import AsyncStorage from '@react-native-async-storage/async-storage';

// Log levels with numeric values for easy comparison
export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  NONE = 4
}

// Configuration
const LOG_STORAGE_KEY = 'app_logs';
const MAX_LOG_SIZE = 100; // Maximum number of logs to keep in storage
const DEFAULT_LOG_LEVEL = LogLevel.DEBUG; // Changed to DEBUG to show all logs
const EXPORT_PATH = FileSystem.documentDirectory + 'app_logs.txt';

// Log entry interface
interface LogEntry {
  timestamp: number;
  level: LogLevel;
  tag: string;
  message: string;
  data?: any;
}

// In-memory log storage
let memoryLogs: LogEntry[] = [];
let currentLogLevel = DEFAULT_LOG_LEVEL;

// Initialize logger
export const initLogger = async (logLevel?: LogLevel): Promise<void> => {
  try {
    // Set log level from parameter or AsyncStorage
    if (logLevel !== undefined) {
      currentLogLevel = logLevel;
      await AsyncStorage.setItem('app_log_level', logLevel.toString());
    } else {
      const storedLevel = await AsyncStorage.getItem('app_log_level');
      if (storedLevel !== null) {
        currentLogLevel = parseInt(storedLevel, 10);
      }
    }
    
    // Load any cached logs
    await loadLogs();
    
    // Log initialization
    log(LogLevel.INFO, 'Logger', `Logger initialized with level: ${LogLevel[currentLogLevel]}`);
  } catch (error) {
    console.error('Error initializing logger:', error);
  }
};

// Log a message
export const log = async (
  level: LogLevel,
  tag: string,
  message: string,
  data?: any
): Promise<void> => {
  // Create log entry
  const entry: LogEntry = {
    timestamp: Date.now(),
    level,
    tag,
    message,
    data: data ? JSON.parse(JSON.stringify(data)) : undefined
  };
  
  // Add to memory logs
  memoryLogs.push(entry);
  
  // Keep only the most recent logs in memory
  if (memoryLogs.length > MAX_LOG_SIZE) {
    memoryLogs = memoryLogs.slice(-MAX_LOG_SIZE);
  }
  
  // Always log to console for auth-related logs
  const logMethod = getConsoleMethod(level);
  const formattedTime = new Date(entry.timestamp).toISOString();
  const logData = data ? JSON.stringify(data, null, 2) : '';
  
  // Force console output for auth-related logs
  if (tag.includes('SquareAuth')) {
    console.log(`🔐 [${formattedTime}] [${LogLevel[level]}] [${tag}] ${message}`, logData);
  } else if (__DEV__ || level >= LogLevel.ERROR) {
    logMethod(`[${formattedTime}] [${LogLevel[level]}] [${tag}] ${message}`, logData);
  }
  
  // Persist logs if error level
  if (level >= LogLevel.ERROR) {
    await persistLogs();
  }
};

// Convenience methods for different log levels
export const debug = (tag: string, message: string, data?: any): void => {
  log(LogLevel.DEBUG, tag, message, data);
};

export const info = (tag: string, message: string, data?: any): void => {
  log(LogLevel.INFO, tag, message, data);
};

export const warn = (tag: string, message: string, data?: any): void => {
  log(LogLevel.WARN, tag, message, data);
};

export const error = (tag: string, message: string, data?: any): void => {
  log(LogLevel.ERROR, tag, message, data);
};

// Get all logs
export const getLogs = (): LogEntry[] => {
  return [...memoryLogs];
};

// Clear all logs
export const clearLogs = async (): Promise<void> => {
  memoryLogs = [];
  await AsyncStorage.removeItem(LOG_STORAGE_KEY);
  log(LogLevel.INFO, 'Logger', 'Logs cleared');
};

// Export logs to a file
export const exportLogs = async (): Promise<string> => {
  try {
    const logText = memoryLogs
      .map(entry => {
        const time = new Date(entry.timestamp).toISOString();
        const level = LogLevel[entry.level];
        const data = entry.data ? `\nData: ${JSON.stringify(entry.data, null, 2)}` : '';
        return `[${time}] [${level}] [${entry.tag}] ${entry.message}${data}`;
      })
      .join('\n\n');
    
    await FileSystem.writeAsStringAsync(EXPORT_PATH, logText);
    
    log(LogLevel.INFO, 'Logger', `Logs exported to ${EXPORT_PATH}`);
    return EXPORT_PATH;
  } catch (error) {
    console.error('Error exporting logs:', error);
    throw error;
  }
};

// Helper function to get the appropriate console method
const getConsoleMethod = (level: LogLevel): (message: string, ...optionalParams: any[]) => void => {
  switch (level) {
    case LogLevel.DEBUG:
      return console.debug;
    case LogLevel.INFO:
      return console.info;
    case LogLevel.WARN:
      return console.warn;
    case LogLevel.ERROR:
      return console.error;
    default:
      return console.log;
  }
};

// Load logs from storage
const loadLogs = async (): Promise<void> => {
  try {
    const storedLogs = await AsyncStorage.getItem(LOG_STORAGE_KEY);
    if (storedLogs) {
      const parsedLogs = JSON.parse(storedLogs) as LogEntry[];
      memoryLogs = parsedLogs;
    }
  } catch (error) {
    console.error('Error loading logs:', error);
  }
};

// Persist logs to storage
const persistLogs = async (): Promise<void> => {
  try {
    await AsyncStorage.setItem(LOG_STORAGE_KEY, JSON.stringify(memoryLogs));
  } catch (error) {
    console.error('Error persisting logs:', error);
  }
};

// Initialize the logger on import
initLogger();

export default {
  debug,
  info,
  warn,
  error,
  log,
  getLogs,
  clearLogs,
  exportLogs,
  initLogger,
  LogLevel
}; 