import { useLanguage } from "@/i18n/LanguageContext";

const Footer = () => {
  const { t } = useLanguage();
  const currentYear = new Date().getFullYear();

  return (
    <footer className="py-12 px-6 border-t border-border">
      <div className="container max-w-4xl mx-auto">
        <div className="flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="flex items-center gap-3">
            <span className="text-heading-md font-semibold text-foreground">Adless</span>
          </div>

          <nav className="flex items-center gap-8">
            <a href="#" className="text-body-sm text-muted-foreground hover:text-foreground transition-colors">
              {t('privacyPolicy')}
            </a>
            <a href="#" className="text-body-sm text-muted-foreground hover:text-foreground transition-colors">
              {t('terms')}
            </a>
            <a href="#" className="text-body-sm text-muted-foreground hover:text-foreground transition-colors">
              {t('support')}
            </a>
          </nav>
        </div>

        <div className="mt-8 pt-6 border-t border-border text-center">
          <p className="text-body-sm text-muted-foreground">
            © {currentYear} Adless. {t('copyright')}
          </p>
        </div>
      </div>
    </footer>
  );
};

export default Footer;
