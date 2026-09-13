import { createContext, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";
import { translations } from "./translations";
import type { Language, TranslationKey } from "./translations";

interface LanguageContextType {
  language: Language;
  setLanguage: (lang: Language) => void;
  t: (key: TranslationKey) => string;
}

const LanguageContext = createContext<LanguageContextType | undefined>(undefined);

const detectLanguage = (): Language => {
  const stored = localStorage.getItem("adless-language");
  if (stored && ["en", "pt", "es"].includes(stored)) {
    return stored as Language;
  }

  const langCode = (navigator.language || "en").toLowerCase();
  if (langCode.startsWith("pt")) return "pt";
  if (langCode.startsWith("es")) return "es";
  return "en";
};

type LanguageProviderProps = {
  children: ReactNode;
  initialLanguage?: Language;
};

export function LanguageProvider({ children, initialLanguage }: LanguageProviderProps) {
  const [language, setLanguageState] = useState<Language>(initialLanguage ?? "en");

  useEffect(() => {
    if (!initialLanguage) {
      setLanguageState(detectLanguage());
    }
  }, [initialLanguage]);

  useEffect(() => {
    document.documentElement.lang = language === "pt" ? "pt-BR" : language;
  }, [language]);

  const setLanguage = (lang: Language) => {
    localStorage.setItem("adless-language", lang);
    setLanguageState(lang);
  };

  const t = (key: TranslationKey): string => {
    return translations[language][key] || translations.en[key] || key;
  };

  return (
    <LanguageContext.Provider value={{ language, setLanguage, t }}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage() {
  const context = useContext(LanguageContext);
  if (!context) {
    throw new Error("useLanguage must be used within a LanguageProvider");
  }
  return context;
}
