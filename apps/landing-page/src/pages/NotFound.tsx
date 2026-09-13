import { Link, useLocation } from "react-router-dom";
import { useEffect } from "react";
import { ArrowLeft } from "lucide-react";
import Footer from "@/components/Footer";
import LanguageSelector from "@/components/LanguageSelector";
import Seo from "@/components/Seo";
import ThemeToggle from "@/components/ThemeToggle";
import adlessLogo from "@/assets/adless-logo.webp";
import { useLanguage } from "@/i18n/LanguageContext";
import { legalUi, notFoundUi } from "@/i18n/translations";
import { languageHomePath } from "@/lib/site";

const NotFound = () => {
  const location = useLocation();
  const { language } = useLanguage();
  const copy = notFoundUi[language];
  const ui = legalUi[language];
  const languageHome = languageHomePath(language);

  useEffect(() => {
    console.error("404 Error: Page not found");
  }, [location.pathname]);

  return (
    <div className="min-h-screen bg-background text-foreground">
      <Seo
        title={`${copy.title} — Adless`}
        description={copy.description}
        path={location.pathname}
        language={language}
        noIndex
      />

      <header className="border-b border-border px-6 py-5">
        <div className="mx-auto max-w-6xl pr-24">
          <Link
            to={languageHome}
            aria-label={ui.back}
            className="inline-flex items-center gap-3 rounded-xl font-semibold"
          >
            <img
              src={adlessLogo}
              alt=""
              width="512"
              height="512"
              className="h-10 w-10 rounded-xl shadow-apple-sm"
            />
            <span>Adless</span>
          </Link>
        </div>
        <LanguageSelector />
        <ThemeToggle />
      </header>

      <main className="relative isolate flex min-h-[calc(100vh-17rem)] items-center overflow-hidden px-6 py-20">
        <div
          aria-hidden="true"
          className="absolute inset-0 -z-10 bg-gradient-to-b from-secondary/80 via-background to-background"
        />
        <div
          aria-hidden="true"
          className="absolute left-1/2 top-16 -z-10 h-72 w-72 -translate-x-1/2 rounded-full bg-accent/10 blur-3xl sm:h-96 sm:w-96"
        />

        <div className="mx-auto w-full max-w-4xl text-center">
          <p className="text-xs font-semibold tracking-[0.2em] text-muted-foreground">
            {copy.eyebrow}
          </p>
          <p
            aria-hidden="true"
            className="mt-5 text-[7rem] font-semibold leading-none tracking-[-0.08em] text-foreground/10 sm:text-[10rem]"
          >
            404
          </p>
          <h1 className="-mt-5 text-4xl font-semibold leading-tight tracking-tight sm:-mt-8 sm:text-6xl">
            {copy.title}
          </h1>
          <p className="mx-auto mt-6 max-w-xl text-lg leading-relaxed text-muted-foreground">
            {copy.description}
          </p>
          <Link
            to={languageHome}
            className="mt-9 inline-flex items-center gap-2 rounded-xl bg-foreground px-6 py-3.5 font-medium text-background shadow-apple-sm transition-transform hover:scale-[1.02] active:scale-[0.98]"
          >
            <ArrowLeft size={18} />
            {copy.action}
          </Link>
        </div>
      </main>

      <Footer />
    </div>
  );
};

export default NotFound;
