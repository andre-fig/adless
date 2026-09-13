import { useEffect, useRef, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { useLanguage } from "@/i18n/LanguageContext";
import { legalUi } from "@/i18n/translations";
import type { Language } from "@/i18n/translations";
import { languageHomePath } from "@/lib/site";

const languages: { code: Language; flag: string; name: string }[] = [
  { code: "en", flag: "🇺🇸", name: "English" },
  { code: "pt", flag: "🇧🇷", name: "Português" },
  { code: "es", flag: "🇪🇸", name: "Español" },
];

const localizedTarget = (language: Language, pathname: string) => {
  const legalSuffix = ["/privacy", "/terms", "/support"].find((suffix) =>
    pathname.endsWith(suffix),
  );
  const home = languageHomePath(language);
  return legalSuffix ? `${home.slice(0, -1)}${legalSuffix}` : home;
};

const LanguageSelector = () => {
  const { language, setLanguage } = useLanguage();
  const { pathname } = useLocation();
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const currentLang = languages.find((item) => item.code === language) ?? languages[0];

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const handleSelect = (lang: Language) => {
    setLanguage(lang);
    setIsOpen(false);
  };

  return (
    <div ref={dropdownRef} className="fixed top-5 right-[4.5rem] z-50">
      <button
        onClick={() => setIsOpen(!isOpen)}
        onKeyDown={(event) => {
          if (event.key === "Escape") setIsOpen(false);
        }}
        className="w-10 h-10 rounded-full bg-card shadow-apple-md flex items-center justify-center border border-border/50 transition-all duration-300 hover:shadow-apple-lg hover:scale-105 active:scale-95 text-lg"
        aria-label={legalUi[language].language}
        aria-expanded={isOpen}
      >
        {currentLang.flag}
      </button>

      {isOpen && (
        <div
          className="absolute top-12 right-0 bg-card rounded-xl shadow-apple-lg border border-border/50 overflow-hidden min-w-[140px] animate-scale-in"
          style={{ animationFillMode: "both" }}
        >
          {languages.map((item) => (
            <Link
              key={item.code}
              to={localizedTarget(item.code, pathname)}
              hrefLang={item.code === "pt" ? "pt-BR" : item.code}
              onClick={() => handleSelect(item.code)}
              className={`w-full px-4 py-3 flex items-center gap-3 transition-colors text-left ${
                language === item.code
                  ? "bg-accent/10 text-accent"
                  : "hover:bg-secondary text-foreground"
              }`}
            >
              <span className="text-lg">{item.flag}</span>
              <span className="text-body-sm font-medium">{item.name}</span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
};

export default LanguageSelector;
