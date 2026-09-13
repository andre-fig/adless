import { useLanguage } from "@/i18n/LanguageContext";
import { languageHomePath } from "@/lib/site";

const Footer = () => {
  const { language, t } = useLanguage();
  const currentYear = new Date().getFullYear();
  const localizedRoot = languageHomePath(language).slice(0, -1);

  return (
    <footer className="py-12 px-6 border-t border-border">
      <div className="container max-w-4xl mx-auto">
        <div className="flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="flex items-center gap-3">
            <span className="text-heading-md font-semibold text-foreground">Adless</span>
          </div>

          <nav className="flex flex-wrap justify-center items-center gap-x-6 gap-y-3">
            <a href={`${localizedRoot}/privacy`} className="text-body-sm text-muted-foreground hover:text-foreground transition-colors">
              {t('privacyPolicy')}
            </a>
            <a href={`${localizedRoot}/terms`} className="text-body-sm text-muted-foreground hover:text-foreground transition-colors">
              {t('terms')}
            </a>
            <a href={`${localizedRoot}/support`} className="text-body-sm text-muted-foreground hover:text-foreground transition-colors">
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
