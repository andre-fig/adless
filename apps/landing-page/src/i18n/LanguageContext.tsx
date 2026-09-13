import { createContext, useContext, useState, useEffect } from 'react';
import type { ReactNode } from 'react';
import { translations } from './translations';
import type { Language, TranslationKey } from './translations';

interface LanguageContextType {
  language: Language;
  setLanguage: (lang: Language) => void;
  t: (key: TranslationKey) => string;
}

const LanguageContext = createContext<LanguageContextType | undefined>(undefined);

// Detect language from browser/system
const detectLanguage = (): Language => {
  // Check localStorage first
  const stored = localStorage.getItem('adless-language');
  if (stored && ['en', 'pt', 'es'].includes(stored)) {
    return stored as Language;
  }

  // Get browser language
  const browserLang = navigator.language || 'en';
  const langCode = browserLang.toLowerCase();

  // Portuguese (Brazil, Portugal)
  if (langCode.startsWith('pt')) {
    return 'pt';
  }

  // Spanish (Spain, Latin America)
  if (langCode.startsWith('es')) {
    return 'es';
  }

  // Default to English
  return 'en';
};

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<Language>('en');
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    document.documentElement.lang = language === 'pt' ? 'pt-BR' : language;
  }, [language]);

  useEffect(() => {
    const detected = detectLanguage();
    setLanguageState(detected);
    setMounted(true);
  }, []);

  const setLanguage = (lang: Language) => {
    localStorage.setItem('adless-language', lang);
    setLanguageState(lang);
  };

  const t = (key: TranslationKey): string => {
    return translations[language][key] || translations.en[key] || key;
  };

  // Prevent hydration mismatch
  if (!mounted) {
    return (
      <LanguageContext.Provider value={{ language: 'en', setLanguage, t: (key) => translations.en[key] }}>
        {children}
      </LanguageContext.Provider>
    );
  }

  return (
    <LanguageContext.Provider value={{ language, setLanguage, t }}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage() {
  const context = useContext(LanguageContext);
  if (!context) {
    throw new Error('useLanguage must be used within a LanguageProvider');
  }
  return context;
}
