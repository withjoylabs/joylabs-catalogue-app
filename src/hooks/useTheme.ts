import { useState, useEffect, useCallback } from 'react';
import { Appearance, ColorSchemeName } from 'react-native';
import { lightTheme, darkTheme } from '../themes';
import { AppTheme } from '../types';

export const useTheme = (): {
  theme: AppTheme;
  isDarkMode: boolean;
  toggleTheme: () => void;
  setThemeMode: (mode: 'light' | 'dark' | 'system') => void;
} => {
  const [themeMode, setThemeMode] = useState<'light' | 'dark' | 'system'>('system');
  const [isDarkMode, setIsDarkMode] = useState<boolean>(
    Appearance.getColorScheme() === 'dark'
  );

  // Update theme when system theme changes
  useEffect(() => {
    const subscription = Appearance.addChangeListener(({ colorScheme }) => {
      if (themeMode === 'system') {
        setIsDarkMode(colorScheme === 'dark');
      }
    });

    return () => subscription.remove();
  }, [themeMode]);

  // Toggle between light and dark themes
  const toggleTheme = useCallback(() => {
    if (themeMode === 'system') {
      setThemeMode(isDarkMode ? 'light' : 'dark');
      setIsDarkMode(!isDarkMode);
    } else {
      setIsDarkMode(!isDarkMode);
      setThemeMode(isDarkMode ? 'light' : 'dark');
    }
  }, [isDarkMode, themeMode]);

  // Set the theme mode directly
  const setThemeModeCallback = useCallback((mode: 'light' | 'dark' | 'system') => {
    setThemeMode(mode);
    if (mode === 'system') {
      setIsDarkMode(Appearance.getColorScheme() === 'dark');
    } else {
      setIsDarkMode(mode === 'dark');
    }
  }, []);

  return {
    theme: isDarkMode ? darkTheme : lightTheme,
    isDarkMode,
    toggleTheme,
    setThemeMode: setThemeModeCallback,
  };
}; 