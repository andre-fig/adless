import { useState, useRef, useEffect } from 'react';
import { useLanguage } from '@/i18n/LanguageContext';
import type { Language } from '@/i18n/translations';

const languages: { code: Language; flag: string; name: string }[] = [
  { code: 'en', flag: '🇺🇸', name: 'English' },
  { code: 'pt', flag: '🇧🇷', name: 'Português' },
  { code: 'es', flag: '🇪🇸', name: 'Español' },
];

const LanguageSelector = () => {
  const { language, setLanguage } = useLanguage();
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const currentLang = languages.find(l => l.code === language) || languages[0];

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleSelect = (lang: Language) => {
    setLanguage(lang);
    setIsOpen(false);
  };

  return (
    <div ref={dropdownRef} className="fixed top-5 right-[4.5rem] z-50">
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="w-10 h-10 rounded-full bg-card shadow-apple-md flex items-center justify-center border border-border/50 transition-all duration-300 hover:shadow-apple-lg hover:scale-105 active:scale-95 text-lg"
        aria-label="Select language"
      >
        {currentLang.flag}
      </button>

      {isOpen && (
        <div className="absolute top-12 right-0 bg-card rounded-xl shadow-apple-lg border border-border/50 overflow-hidden min-w-[140px] animate-scale-in" style={{ animationFillMode: 'both' }}>
          {languages.map((lang) => (
            <button
              key={lang.code}
              onClick={() => handleSelect(lang.code)}
              className={`w-full px-4 py-3 flex items-center gap-3 transition-colors text-left ${
                language === lang.code
                  ? 'bg-accent/10 text-accent'
                  : 'hover:bg-secondary text-foreground'
              }`}
            >
              <span className="text-lg">{lang.flag}</span>
              <span className="text-body-sm font-medium">{lang.name}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
};

export default LanguageSelector;
